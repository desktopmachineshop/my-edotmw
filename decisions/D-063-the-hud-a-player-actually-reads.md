### D-063 · 2026-08-06 · Accepted — the HUD a player actually reads, and a view that turns
**Decision:** The HUD's contents are chosen for what a player can ACT on,
and the camera gains a yaw.

1. **Top bar:** resources, then `12/40 squads`, then the match clock, then
   a **Menu** button at the right edge.
2. **The ghost count is gone from the HUD.** It measured fog of war
   working — a diagnostic, kept in the capture verdict where measurements
   belong, not in the one line a player reads at a glance.
3. **The view rotates.** Q/E in 15-degree steps, Ctrl+wheel in 7.5-degree
   steps, plain wheel still zooms. A **compass** under the top-right
   snaps back to north on click.
4. **The selection panel handles a mixed force**: named for what it
   contains, strength summed per squad, and only actions EVERY selected
   squad can perform.
5. **An in-game menu that does not pause**, with Resume, Settings, Save
   (disabled — see below), Leave match and Exit.
6. **Settings** covers only what there is a real system for: fullscreen,
   camera pan speed, HUD scale (with an automatic default), persisted to
   `user://settings.cfg`.

**Why the clock and the cap come from the SERVER.** The cap is MapConfig
data the client has no copy of, and a client that read a local `.tres`
could print a ceiling different from the one the server enforces. The
clock is worse: a timer each client ran for itself would show every
player a different match length and drift further apart the longer the
game ran — and this project is aiming at 1–2 hour matches (D-056), which
is long enough for that to become visible. So `WELCOME` carries the cap
and the server's tick, and the client re-anchors on the tick already
present in every `STATE_HASH`. At a fixed 10 Hz (D-020) the tick count IS
the elapsed time, so the clock cannot disagree with the simulation and
costs no bandwidth of its own — D-003's derive-between-messages pattern,
the same one construction progress and the production countdown use.

**Why the squad count is not `curves.size()`.** That is every squad on
screen, including other players' — a number with nothing to do with the
ceiling printed beside it. It is counted the way
`MatchState.has_squad_capacity` counts: this player's own living squads,
gatherers included. Nor is it `squads.size()`, which only ever grows
(nothing removes a dead squad from the list of ids this client was told
it owns) and would produce "41/40".

**Rotation was cheap because nothing ever assumed a fixed heading.**
Cell-picking goes through `project_ray_*`, selection and culling through
`unproject_position`, and terrain tiling through lattice offsets around
the camera target — so all three follow the camera without being told.
The only thing that had to change was WASD, which now pans relative to
where the camera looks: after a 90-degree turn the world axis that used
to mean "up the screen" means "right", and panning in world space is the
standard complaint about RTS cameras that get this wrong.

**The compass turns its dial, not its needle.** A compass answers "which
way am I facing", so the world's north moves around the ring while the
direction you are looking stays fixed at the top. A spinning needle over
fixed letters is a magnetic compass — a different instrument answering a
different question, and an easy thing to build by accident because it
looks almost right.

**Why the menu does not pause, and why that is not a shortcut.** The
server is the authority and runs its own clock (D-002/D-020). A client
cannot pause a match any more than it can move a squad, and in
multiplayer it must not: "pause" would either stop everyone else's game
or — worse — stop only this player's view while their army carried on
being attacked. So the menu is an overlay on a running match and says so
on its face. One consequence is load-bearing: the backdrop must not
swallow input, or a player could not react to what they can see happening
behind it.

**Save is a disabled button, deliberately.** There is no save system:
the authority is the server, so a save is a snapshot of ITS state —
`SquadSim`, `BuildingSim`, `Economy`, `MatchState`, the RNG position and
the tick — and none of that is serialised anywhere. The button is present
and disabled with a tooltip saying why, rather than absent (which hides
the gap) or present-and-silent (which would be the
declared-and-unread shape of D-061 and D-055, built on purpose). Owner's
call, 2026-08-06: saves get their own milestone.

**Rejected alternatives:**
- *A settings screen with graphics quality, resolution and keybind
  remapping* (rejected — there is no LOD toggle to bind, no resolution
  list, and no keybind indirection: `_handle_key` reads keycodes straight
  off the event. Every one of those would be a control that appears to do
  something and does not).
- *Plain wheel to rotate* (rejected — zoom is the constant gesture and
  keeps the bare wheel; rotation is occasional and can afford Ctrl).
- *Pausing the match from the menu* (rejected — see above; not
  implementable in a client-server game with an authoritative server).
- *A "spectate" state on leaving a match* (rejected — leaving disconnects,
  and D-033's ordinary rule then wipes the abandoned army, exactly as a
  dropped connection does. Inventing a half-way state would be a rule
  nobody asked for).

**Consequences:** Q and E are now taken. `BUILD_KEYS`/`TRAIN_KEYS` are
driven by `OS.get_keycode_string`, so a future building or unit given the
letter Q or E would silently steal it — the rotation check runs first,
which keeps that a deliberate choice rather than a race between two
lookups. Rotation also means the minimap's view-bounds box is drawn from
a rotated frustum; it is derived from the camera, so it follows, but it
is now a quadrilateral rather than an axis-aligned box.

**An intermittent `test-load` failure was seen while verifying this, and
it is NOT this change.** One run in several reported `known_squads_max=4
buildings_known=0` — every bot still holding only its founding party and
nobody having built anything — on a run that otherwise ticked its full
137 s with 0 desyncs. The same numbers reproduce with these changes
stashed, and the immediately following run was clean (`known_squads_max=35
buildings_known=7`, 522,600 bytes, 65.2 µs/squad at 52 squads, 0 dropped
ticks).

The likely amplifier is worth writing down: `bot_client.gd` attempts to
found a town hall EXACTLY ONCE, at `_orders_issued == 0`. Nothing retries
and nothing checks whether it worked, so any single refusal or lost
opening order leaves that bot with no base for the whole run — and since
every bot opens identically, a condition that hits one tends to hit all
four. That makes the harness's most important precondition a single point
of failure. Not fixed here (it is the load-test harness, not the game),
but it is the first thing to look at if this recurs.

**Revisit trigger:** if the camera ever gains PITCH as well as yaw,
`_cell_under`'s flat-plane assumption (`distance := -from.y /
direction.y`) still holds, but the fixed `height * 0.6` offset stops
being a sensible framing and the camera model needs rethinking rather
than extending.

---
