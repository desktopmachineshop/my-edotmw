**M8's first rung is built: `just export` produces the shipping builds**
(`D-20260827-the-build-is-exported-from-one-version`, #178, D-094
criterion 1, 2026-08-27). This is the first M8 code of any kind —
`docs/status/m8-plan.md` describes the milestone as planned and not
built, and that is now true of everything in it except this.

```
just bootstrap-export-templates   # ~1.3 GB, once, into tools/
just export                       # all three, or: export windows-client
```

Three presets ship in a committed `export_presets.cfg`: **Windows
Client**, **Windows Server**, **Linux Server**. Measured on 2026-08-27,
native, from this worktree: 267 MB / 267 MB / 233 MB, about 90 s for all
three after a warm import.

**Verified rather than asserted, which for a build means it was run.**
The exported Windows server was launched headless and the exported
Windows client connected to it: 143 terrain chunks built, a town hall
founded, 2 squads drawn, **0 squad desyncs in 7 checks and 0 building
desyncs in 7 checks**, both binaries printing `my-edotmw 0.1.0-alpha` as
their first line. That is #178's own acceptance condition, and it needed
a Windows *server* preset to be reachable at all on the machine this
project is developed on — the decision entry says why that is not scope
creep.

Six things to know before touching any of it:

- **The version is a literal in `project.godot`
  (`application/config/version`) and nothing else may name it.**
  `build_version.gd` reads it at runtime, the `export` recipe reads the
  same line with `grep`, and `tests/test_export.gd` fails if a second
  script names the setting — the D-046-criterion-3 pattern. Not a git
  sha and not a timestamp, because D-081 requires two clean clones of
  one commit to export the same bytes, and because "both binaries print
  the same version" must be a statement about what is in them rather
  than about when they were built.
- **An exported binary's entry point is a FEATURE TAG.** The checkout
  has always been driven by an explicit scene (`godot --path .
  server.tscn`), which an exported build does not accept. So
  `run/main_scene` is the client and `run/main_scene.server` is the
  server, and the two server presets carry `custom_features="server"`.
  **Either half alone fails silently** — a server preset that loses its
  tag exports a working CLIENT under the server's filename — so one test
  asserts both halves together, and it was observed to fail.
- **The server presets are NOT `dedicated_server=true`.** That mode
  strips visual resources, and this project discovers `/units`, `/civs`,
  `/maps` and the rest by scanning directories rather than by scene
  dependency, so what the stripper would keep is not something the code
  can reason about from outside. A full template run with `--headless`
  is what docker has proven since D-014. Smaller server binaries are a
  later measurement, not the first build anybody installs.
- **Export templates live under `tools/`**, via Godot's self-contained
  marker (`tools/_sc_`), because `bootstrap.ps1` promises a fresh clone
  installs nothing system-wide and `just nuke` promises pure source. The
  templates version is checked against `.godot-version` before
  installing: a 4.7.1 build exported with 4.7.0 templates **fails at
  load, not at export** — on a player's machine, not on the builder's.
- **`export_filter` is `all_resources`, not the dependency walk.** A
  dependency-walked export would ship a game missing its own roster, and
  would do it silently, for exactly the reason above. The exclude list
  drops `tests/`, `addons/gut/`, `art/` and the docs.
- **A build cannot write `res://`, and the first exported server said
  so** — `ReplayLog` targets `res://artifacts` and fails at start-up
  with a `push_error` nobody in a released build can see, so an exported
  build records **no replays at all** (D-016). Filed as **#201**, not
  fixed here.

**Stopped at the boundary, deliberately.** D-094 criterion 2 (steamcmd
upload to a private depot, a fresh machine installing from Steam) needs
Steam credentials, an app id, a depot only the owner can create and a
second machine. None of that is reachable from a worktree, and it is
#182+.
