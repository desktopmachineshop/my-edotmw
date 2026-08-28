### D-20260828 · Accepted — the Steam boundary is built; and D-093's GDExtension premise is measured false

**Two things, and they are separable on purpose.** The first is #181's
work and is settled. The second is a finding that invalidates a named
mechanism in D-093 and is **left open for the owner**, because choosing
its replacement is a toolchain decision with consequences for D-001,
D-014 and #178.

---

## 1. The boundary exists, and it is indifferent to how Steam arrives

`steam_platform.gd` is the one script in this project that names Steam,
and `tests/test_steam_boundary.gd` fails if any other `.gd` names the API
— the falsifiable-by-grep pattern of D-046 criterion 3 and D-086's
lighting guard. That test is the whole reason D-021 ("GDScript only, no
C#") could be amended by exactly one category without the amendment
becoming a hole: the rule is structural rather than remembered. It was
**observed to fail** before being trusted (a Steam call added to
`economy.gd`; red, naming the file; reverted).

Detection is `Engine.has_singleton("Steam")` /
`ClassDB.class_exists("Steam")`, and **that answers identically whether
GodotSteam arrives as a GDExtension or as a modified engine build.** The
boundary was built before any Steam feature precisely so the transport
(#184), the identity (#186) and the lobbies (#187) can be written against
a fixed surface whichever way section 2 is resolved.

**The scan reads CODE, not prose, and that is not a loosening.** Three
shipped files already contain the word: `client.gd` and `squad_sim.gd`
describe a routed squad fleeing *"under its own steam"*, and
`net_protocol.gd` explains that *"Steam's rolling updates make mixed
versions routine"* as #179's rationale. All three are correct and none
calls anything. D-093's rule is about calls, so whole-line comments are
stripped first. The alternative — a guard that fires on an English word
in a comment — is a guard people learn to edit rather than obey, and
#204 records this repo already having one of those.

**Absent Steam is asserted, not assumed** (D-094 criterion 7): the suite
checks that `SteamPlatform.available()` is false here, that `steam_id()`
returns **0** and `persona_name()` returns **""** — specific values,
because D-090 rebinds a seat by SteamID and a seat rebound by a
fabricated id is a seat anybody could claim — and that neither the
Dockerfile nor `docker-compose.yml` mentions Steam at all.

`just doctor` prints the **pairing** (`.godotsteam-version` beside
`.godot-version`) rather than an availability answer of its own, because
a mismatched pair **fails at load, not at build** — on a player's
machine, not the builder's — and because a second definition of "Steam is
present" in shell would be free to disagree with the boundary's.

---

## 2. GodotSteam does not ship a GDExtension, and D-093 assumes it does

**D-093 says:** *"Steamworks reaches this project through the
**GodotSteam GDExtension**"*, *"GodotSteam's GDExtension build, not the
.NET binding"*, and *"the extension binary is a pinned dependency fetched
by bootstrap (the `tools/` pattern), never committed"*.

**Measured, 2026-08-28, against GitHub's release API.** Every release of
every repository in the GodotSteam organisation — `GodotSteam`,
`GodotSteam-Server`, `MultiplayerPeer` (archived), `Skillet` (archived) —
across the whole v3.x and v4.x history, ships **only** assets of these
shapes:

```
godotsteam-g472-s165-gs422-templates.tar.xz     <- Godot export templates
macos-g472-s165-gs422-editor.tar.xz             <- a Godot editor
win64-g451-s162-gs4162-mp.tar.xz                <- a Godot editor
```

That is a **modified Godot engine**: an editor and a matching set of
export templates with Steamworks compiled in. There is no
`.gdextension`, no `lib*.so`/`.dll` extension binary, and no
`GodotSteam-GDExtension` repository. Scanned every release's asset list;
GDExtension assets: none, anywhere.

**Why this is not a detail.** D-093's mechanism was chosen partly because
it is "toolchain-cheap and reversible". A custom engine is neither in the
same way, and it collides with three things this project already relies
on:

- **D-001 / `.godot-version`.** The engine is pinned and both the
  container build and `just bootstrap` read that pin. A Steam build means
  `bootstrap` fetches GodotSteam's Godot instead of upstream's, and the
  version pairing becomes engine-and-Steamworks rather than a version
  string.
- **#178's export templates.** `just bootstrap-export-templates` fetches
  upstream templates for the pinned version. A Steam build must export
  with **GodotSteam's** templates, or the shipped binary has no Steam in
  it — and, per that decision's own warning, a mismatched template pair
  fails at load rather than at build.
- **D-093's fallback claim.** *"The entire existing test estate runs
  Steam-less by construction"* is true of a GDExtension you simply do not
  install. With a custom engine, the honest version is narrower and still
  fine: docker keeps building **upstream** Godot, so containers have no
  Steam by construction; what changes is that a developer's native
  toolchain and the shipped build use a different engine binary from the
  container's. That is a real difference and it should be decided rather
  than discovered.

Also worth recording: GodotSteam's current release (**v4.22**) targets
Godot **4.7.2**, while `.godot-version` is **4.7.1**; **v4.21** is the
release that targets 4.7.1. `.godotsteam-version` is pinned to **v4.21**
for that reason, and `just doctor` prints the pair.

**Deliberately NOT done here: no `bootstrap-steam` recipe.** Writing one
would mean writing a fetch for an artifact that does not exist, and a
recipe that has never been run and cannot work is the one thing this
repo's own rules forbid outright. The boundary and its guard are worth
having now regardless of the answer; the fetch is not.

**The options, for whoever takes it** (this is the open half):

1. **Adopt the custom engine.** `.godot-version` gains a GodotSteam
   variant; `bootstrap` and `bootstrap-export-templates` learn to fetch
   it; docker keeps upstream Godot so the test estate stays Steam-less
   for free. Closest to what GodotSteam actually distributes, and the
   path its documentation assumes.
2. **Build the GDExtension from source.** GodotSteam's repository can be
   compiled as one; this is what D-093 imagined, and it costs a build
   step and a maintained toolchain.
3. **Hand-roll the minimal surface.** D-093 already names this as the
   fallback ladder's last rung, and the boundary script is exactly the
   document of "what is actually used" that makes it estimable — today,
   that is availability, a SteamID and a persona name.

**Revisit trigger:** the owner picking one of the three, at which point
that becomes an entry superseding D-093's mechanism clause (its other two
constraints — one script names Steam, absent Steam costs Steam — are
unaffected and are now enforced); or GodotSteam beginning to publish a
GDExtension, which would make D-093 correct as written and this section
history.
