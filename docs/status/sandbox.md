**The sandbox panel runs the world (D-20260821, amending D-077).** The
in-match dev panel (a separate OS window, opens when the server confirms
sandbox mode) carries: the resource grant; unit and building spawns with
a **"for the ENEMY"** checkbox (the server resolves the first hostile
seat — a client never names a player id, and the archetype resolves
against the TARGET's civ per D-047); **Regen map (new seed)** — the
D-075 return-to-lobby edge plus an immediate restart, seats and sandbox
flags held, seed force-rolled even if pinned, every step the ordinary
tested path rather than a new lifecycle; and the match-wide toggles
moved out of the lobby — instant build, AI economy-only, and
**Resources on/off**, which is consulted at world GENERATION time and so
applies on the next regen (a live bulk node clear would need either a
fog-violating broadcast or a ghost forest of stale trees, and the regen
button is one click away). The lobby shows exactly ONE sandbox checkbox
now.

Worth knowing: the panel's toggles ride the same admin-gated
`LOBBY_SET_OPTION` channel the lobby checkboxes always sent — D-077
deliberately never phase-locked it, so nothing new crosses the wire for
them. Regen and the option channel are admin-gated; the per-player
cheats stay any-player. Moving two checkboxes out of the lobby made the
lobby page ~38 design units shorter, which un-shortened a
`test_lobby_layout` fixture window — the "too short" fixture moved to
1366x700, the same "a fixture must actually be what it claims" rule as
the wiped-window trap.

**Same-day follow-ups (amendment in the decision):** cheat building
spawns arm the ORDINARY placement ghost (facing, validity, wall snap; no
builder needed; the wire carries the sub-cell offset so the spawn lands
exactly where the preview stood — D-096's shared-pose rule); a **Freeze
AI** checkbox (fifth sandbox option) makes the server skip the brains
entirely — not a no-op feed, so thawing fires no backlog; and the panel
window sizes itself to its content, capped below the screen.
