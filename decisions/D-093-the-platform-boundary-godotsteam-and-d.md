### D-093 · 2026-08-14 · Accepted — the platform boundary: GodotSteam, and D-021 amended by exactly one category

**Decision:** Steamworks reaches this project through the **GodotSteam
GDExtension**, and D-021 gains a second sanctioned GDExtension
category: **platform integration**. D-021's original category
(performance kernels, on measured evidence only) is untouched and still
has zero members. Three constraints keep the amendment from becoming a
hole:

1. **One script names Steam.** Every Steamworks call lives behind a
   single boundary script (`steam_platform.gd` or equivalent); no other
   `.gd` file mentions Steam at all, and **a test enforces it** — the
   same falsifiable-by-grep pattern as D-046 criterion 3 (no script
   names a civ) and D-086's lighting-rig guard. This is the project's
   proven mechanism for keeping a rule true after everyone stops
   looking.
2. **Absent Steam costs Steam, never the game.** No Steam context —
   docker, CI, bots, LAN, a clone that never installed the extension —
   means the boundary reports unavailable and everything else works
   over ENet exactly as today. The precedent is D-081's empty
   `model_id`: a failed integration degrades fidelity (here: no
   relay, no lobbies, no invites), not function. The entire existing
   test estate runs Steam-less by construction, which is also why the
   Steam path needs its own verification story (D-094).
3. **Still no C#** (D-021's yes/no answer stands): GodotSteam's
   GDExtension build, not the .NET binding; no `.csproj` appears.

**Rationale:** D-088 (relay) and D-089 (lobbies, invites) are
impossible without Steamworks, and Steamworks has no GDScript-native
path. The alternative reading — that D-021 forbids this — would make
D-021 decide product scope, which was never its job; it was a toolchain
cost/reversibility decision, and a pinned prebuilt extension behind one
script is toolchain-cheap and reversible.

**Rejected alternatives:** shipping with no Steamworks at all (steamcmd
upload needs none — but D-088/D-089 die with it); the C# Steamworks
bindings (D-021); hand-rolled GDExtension against the Steamworks SDK
(GodotSteam exists, is maintained, and is the community-standard
binding).

**Consequences:** the extension binary is a pinned dependency fetched
by bootstrap (the `tools/` pattern), never committed; `.godot-version`
gains a sibling pin. `just doctor` learns to report Steam availability.
The boundary script is the natural home for the SteamID identity D-090
needs and the lobby mapping D-089 needs.

**Revisit trigger:** GodotSteam abandonment or a Godot upgrade it lags
badly (the standing risk of any binding); at that point the fallback
ladder is: pin harder, then hand-roll the minimal surface actually used
(sockets, lobbies, identity — small by then, since the boundary script
documents exactly what is used).

---
