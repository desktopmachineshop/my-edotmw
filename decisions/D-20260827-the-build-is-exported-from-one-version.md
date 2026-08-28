### D-20260827 · Accepted — the build is exported from one version, and the server export is a feature tag

**Decision (M8, issue #178, discharging D-094 criterion 1):** `just
export` produces the shipping builds from **committed export presets**,
and the build version is written down in **exactly one place** —
`project.godot`'s `application/config/version`, read at runtime through
`build_version.gd` and at build time by the recipe. Three presets ship:
**Windows Client**, **Windows Server** and **Linux Server**.

Four sub-decisions, each of which had an obvious alternative:

**1. The version is a literal in `project.godot`, not a git sha and not
a timestamp.** It is the one file both readers can already reach: the
engine bakes project settings into the `.pck`, so an exported binary
answers the same as a checkout, and the recipe reads the same line with
`grep`. A sha or a build date would make "two clean clones of one commit
export the same bytes" false by construction — D-081's determinism rule
and #178's own wording — and would turn "both binaries print the same
version" into a statement about *when* they were built rather than about
*what is in them*. `build_version.gd` is all-static and a test forbids
any other script from naming the setting, the same falsifiable-by-grep
shape as D-046 criterion 3.

**2. An exported build's entry point is a FEATURE TAG, not a launcher
scene and not a command-line argument.** This checkout has always been
driven by an explicit scene (`godot --path . server.tscn`), which an
exported binary does not accept — its main scene is baked in. So
`project.godot` gains `run/main_scene="res://client.tscn"` and
`run/main_scene.server="res://server.tscn"`, and the two server presets
carry `custom_features="server"`. Rejected: a small launcher scene that
reads `--server` and loads one or the other, which puts a runtime
decision where a build-time one already exists, and gives every client
build the code path that starts a server. **The pairing is the whole
mechanism and either half alone fails silently** — a server preset that
lost its feature tag exports a perfectly working *client* under the
server's filename — so a test asserts both halves together.

**3. `dedicated_server=false` on the server presets, and `--headless` at
run time.** Godot's dedicated-server export mode strips visual resources
(meshes and textures become placeholders). The server has never been run
under that substitution, and `unit_roster` / `civ_roster` discover their
data by scanning directories rather than by scene dependency, so what
the stripper keeps is not something this project can reason about from
the outside. What *is* proven is a full template run headless: that is
exactly what docker has done since D-014. Smaller server binaries are
worth having later; they are not worth buying with an untested
substitution in the first build anybody installs.

**4. A WINDOWS SERVER preset exists, and it is not scope creep.** #178's
own acceptance line is "the Windows client reaches a match against a
locally run exported server". The development machine is Windows
(D-014's whole premise), so on that machine a Linux binary cannot be the
server that criterion means. It is also what D-088's in-process host
will be exported as. Same presets, same scene switch, one more line in
the recipe.

**Export templates live under `tools/`,** installed by
`just bootstrap-export-templates` into `tools/editor_data/` via Godot's
self-contained-mode marker (`tools/_sc_`). The alternative — the
machine's `%APPDATA%/Godot` — would quietly break two standing promises
at once: `bootstrap.ps1` says a fresh clone installs nothing
system-wide, and `just nuke` says it leaves pure source. 1.3 GB in
neither of those places is the kind of thing nobody notices until a
machine is full. The templates version comes from `.godot-version` and
is verified against the archive's own `version.txt` before installing,
because a 4.7.1 build exported with 4.7.0 templates **fails at load, not
at export** — on the player's machine, not the builder's.

**Rejected alternatives:** *generating `export_presets.cfg` from the
recipe* — it is normally editor-written, and a generated one would drift
from what the editor produces the first time anybody opens the project;
committing it is what makes "from a clean clone" true. *Exporting with
`export_filter="resources"`* (dependency-walked) — this project
discovers `/units`, `/civs`, `/maps`, `/ai`, `/formations` and
`/scenarios` by scanning directories at runtime, so a dependency walk
would ship a game missing its own roster, and would do it silently.
`all_resources` with an exclude list for `tests/`, `addons/gut/`, `art/`
and the docs is the honest shape.

**Consequences:** `just doctor` reports the build version and whether
templates are present (reported, never required — the same rule the art
tooling is reported under: producing a build needs templates, playing
the game does not). `build/` is gitignored. `tests/test_export.gd`
guards the preset/recipe agreement, the single version, the import-first
rule and the feature-tag pairing; every one of its checks was observed
to fail before being trusted. The version string itself is
`0.1.0-alpha` and bumping it is a one-line edit — deliberately, because
the next ticket (#179) puts it on the wire and a refusal message quotes
it.

**Not done here, and stopping at the boundary deliberately:** D-094
criterion 2 (steamcmd upload to a private depot) needs Steam
credentials, an app id and a depot that only the owner can create; and
"a fresh machine installs and runs it from Steam" needs a second
machine. Neither is reachable from this workstation, and both are #182+.

**Revisit trigger:** a measured need for smaller server builds (revisit
`dedicated_server`); a second platform (macOS, or a Linux *client* for
Steam Deck) — that is a new preset and a new decision about what
"shipping platforms" means, not an edit here; or the first time a build
version needs to identify a *specific build* rather than a release,
at which point a build number belongs in a file the release process
writes, never in the engine's project settings.
