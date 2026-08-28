**The Steam boundary exists, and nothing has crossed it yet**
(`D-20260828-godotsteam-does-not-ship-a-gdextension`, #181, D-093,
2026-08-28). `steam_platform.gd` is the one script in this project
allowed to name Steam; `tests/test_steam_boundary.gd` fails if any other
`.gd` names the API. That guard is what lets D-021 — *GDScript only, no
C#* — be amended by exactly one category (platform integration) without
the amendment becoming a hole: the rule is structural rather than
remembered, the same mechanism as D-046 criterion 3's no-script-names-a-civ
and D-086's lighting-rig scan. It was **observed to fail** before being
trusted.

Five things to know:

- **The boundary is indifferent to how Steam arrives.**
  `Engine.has_singleton("Steam")` answers the same whether GodotSteam is
  a GDExtension or a modified engine, which matters because that question
  is now OPEN (below). The boundary was built before any Steam feature so
  the transport (#184), the identity (#186) and the lobbies (#187) can be
  written against a fixed surface either way.
- **The scan reads CODE, not prose.** `client.gd` and `squad_sim.gd`
  describe a routed squad fleeing *"under its own steam"*, and
  `net_protocol.gd` explains that *"Steam's rolling updates make mixed
  versions routine"*. All three are correct and none of them calls
  anything, so whole-line comments are stripped first. A guard that fired
  on an English word in a comment is a guard people learn to edit rather
  than obey — #204 records this repo already having one of those.
- **Absent Steam is ASSERTED, not assumed** (D-094 criterion 7). The
  suite checks `available()` is false here, that `steam_id()` is **0** and
  `persona_name()` is **""** — specific values, because D-090 rebinds a
  seat by SteamID and a seat rebound by a fabricated id is a seat anybody
  could claim — and that neither the Dockerfile nor `docker-compose.yml`
  mentions Steam at all.
- **`just doctor` prints the PAIRING, not an availability verdict.**
  `.godotsteam-version` sits beside `.godot-version` because a mismatched
  pair **fails at load, not at build** — on a player's machine rather than
  the builder's. Availability is a runtime question and the boundary is
  the only thing allowed to answer it; a second definition in shell would
  be free to disagree.

**And the finding that is somebody's decision, not this ticket's: D-093
names a GDExtension, and GodotSteam does not ship one.** Every release of
every repo in that organisation, across the whole v3/v4 history, ships a
**modified Godot engine** — an editor plus matching export templates with
Steamworks compiled in. No `.gdextension`, no extension binary, no
`GodotSteam-GDExtension` repository. That collides with `.godot-version`'s
pin (D-001), with #178's export templates (a Steam build must export with
GodotSteam's templates or the binary has no Steam in it), and with
D-093's "the entire test estate runs Steam-less by construction" — which
stays true for docker, since containers keep building upstream Godot, but
in a narrower way than that sentence implies.

Current GodotSteam **v4.22** targets Godot **4.7.2**; **v4.21** targets
our pinned **4.7.1**, which is what `.godotsteam-version` holds.

**No `bootstrap-steam` recipe was written**, deliberately: it would be a
fetch for an artifact that does not exist, and a recipe that has never
been run and cannot work is the one thing this repo's rules forbid
outright. The decision entry lists the three options (adopt the custom
engine, build the GDExtension from source, or hand-roll the minimal
surface — the boundary script is exactly the "what is actually used"
document that makes the last one estimable) and leaves the choice to the
owner.
