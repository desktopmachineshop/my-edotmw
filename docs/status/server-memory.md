**Server memory is measured on the shipped map ladder, and it is not a
problem** (D-20260818-server-memory-is-quoted-with-its-conditions, #111,
M10 exit criterion 6). The table and its caveats live in that decision;
what belongs here is the shape of the answer and the rules it bought.

Headline, and never quote it without the conditions attached:
**52.6 MB static / 56.3 MB peak at 20 players, 128 squads, 168x194 =
32,592 cells**, and **65.3 MB / 72.3 MB at 20 players, 20 squads,
336x388 = 130,368 cells** — against a stated budget of 256 MB at
D-018's full target on the largest map. Bandwidth on the same run was
193 B/client/s over 20 clients, 0 overruns.

- **A memory figure carries its conditions — players, squads, cells —
  exactly as µs/squad carries a squad count.** The server prints
  `server: MEMORY <static>, <peak> — N player(s), M squad(s), WxH = C
  cells` and `just test-load` surfaces it beside the `final` line.
  Before it, `mem=43.3 MB` rode along at the end of the bandwidth line:
  correct, and impossible to compare with M4's 42.5 MB, because neither
  number said which map it was taken on.
- **The map is the dominant allocator now, and the armies are not** —
  ~140 bytes per cell, while a server with nobody connected and one 300 s
  twenty-player match sat at the same ~71 MiB of container RSS. That is
  the sentence M4's numbers stopped being able to say when the ladder
  moved.
- **PEAK players, not whoever is still connected.** The summary prints
  when the last client leaves, so a live count reads 1 however many
  played — the trap the bandwidth line already fell into once.
- **`EDOTMW_MAP` picks the MapConfig for a `just test-load` run**, and
  `maps/huge.tres` is the ladder's top rung. `just up` brings the server
  up through docker compose, so before this there was no way to
  load-test any map but the default — a large part of why the top of the
  ladder had never been measured.
- **`just test-load` cannot run the Huge map**: the bots' 10 s connect
  timeout expires while the server is still generating 130,368 cells and
  29,013 resource nodes, so the run fails with the server working
  perfectly. Drive it by hand (`just up`, then `just run-bots`) until
  #106's start-up work lands.
- **Static memory is not RSS.** Godot's tracked figure read 52.6 MB
  where the container's resident set was ~71 MiB. Every historical
  number in this repo is the tracked one; keep quoting that, and carry
  RSS beside it rather than instead of it.
