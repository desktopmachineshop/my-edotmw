# D-20260827 · 2026-08-27 · Provisional — a client with no server says so

**Decision:** losing the server puts a message on the CLIENT'S SCREEN,
and that message takes the mouse. Four clauses, deliberately narrow:

1. **The disconnect event is surfaced, not merely printed.**
   `client.gd`'s `EVENT_DISCONNECT` branch calls `_on_connection_lost()`,
   which shows an overlay naming what happened. `print("client:
   disconnected")` stays; it went to stdout and nowhere a player can
   see.
2. **The overlay's backdrop is `MOUSE_FILTER_STOP`**, unlike the defeat
   screen's `IGNORE`. That is the whole "return to a sane state" half:
   the client sends orders from about twenty `_peer.send` sites, and one
   backdrop that swallows clicks is one place, where twenty guards would
   be the same rule written twenty times.
3. **The match is NOT torn down.** `_teardown_match()` frees the
   terrain, the squads and the buildings, so a player who has just lost
   the server would be shown a black screen instead of the last thing
   that happened. The frozen world stays, and the message says it is
   frozen. The overlay therefore has to outlive a teardown, which is
   asserted rather than assumed.
4. **An unattended capture is not covered up.** `just test-client`
   renders a frame and checks the PIXELS; a banner across it would change
   what every one of those checks measures. A capture run
   (`_run_seconds > 0`) pushes a warning to the console its verdict
   already reads from, and keeps drawing what it was asked to draw.

## Rationale

From #162, hit while launching playtest P09. The window looked frozen.
It was not: the server had shut down — correctly, per D-075's "no
humans, no server" — and the client kept its window, kept ~44% of a core
and kept drawing a world that could no longer change, with
`Responding=True` and nothing on screen. From the chair that is a hang,
and it was reported as one.

D-075 was careful about the SERVER side of this lifecycle and the client
side was never written, so the failure is the ordinary shape: a rule
that is absent rather than wrong, and nothing fails.

**Status is Provisional on purpose.** #180 (the pre-lobby main menu)
names this issue as its sibling and says the disconnect should land on
that menu with a message. This is the part that could not wait, written
so that ticket can absorb it: `_on_connection_lost()` is one function
with one caller, and the menu replaces its BODY without touching the
event path or any of the tests below except the one naming the button.

## Rejected alternatives

- **Returning to the lobby.** There is no lobby without a server — the
  lobby IS server state (D-048), broadcast to clients. The screen a
  disconnected client should land on does not exist yet; that is #180.
- **Quitting the process on disconnect.** Honest and hostile: it throws
  away the last frame, the console's desync summary, and any chance of
  reading what happened. It also makes a transient drop unrecoverable
  before reconnection exists (D-090).
- **Tearing the match down and showing the message over nothing.** See
  clause 3. Also the highest-risk option in this file: `_teardown_match`
  freeing something `_ready` built once is precisely how the second
  match after a return to the lobby came up with no terrain for a
  milestone (D-075's amendment).
- **Guarding every `_peer.send` on `_connected`.** Twenty copies of one
  rule. The backdrop is one.
- **Raising the peer timeout / threading the terrain build**, which #162
  also proposes. The terrain freeze it names is already fixed —
  `D-20260818-terrain-builds-a-slice-at-a-time` (#106) builds the ground
  in budgeted slices behind a loading bar — and the message is worth
  having whatever caused the drop, which is the issue's own framing.

## Consequences

- **A never-answered connect attempt is distinguished from a server
  going away.** Both arrive as `EVENT_DISCONNECT`, and "there was never
  one there" is a different thing to tell a player; the second names the
  endpoint it could not reach. Cheap here, and #180 owns the screen it
  becomes.
- **Every check was observed to fail before it was trusted**, including
  the two that scan for a CALLER — that `_ready` builds the overlay, and
  that the disconnect branch calls the handler. Without those, every
  behavioural test in the file would pass on a client that never shows
  anything, which is the D-055/D-106 family this project keeps paying
  for.
- **The lifetime half of `client.gd` is testable and this is the third
  time that has had to be said** (D-075's 2026-08-16 amendment, then
  `D-20260823-a-civs-knobs-are-read-by-the-simulation` for `server.gd`).
  Instantiated, never added to the tree, so `_ready()` does not run.
- **What no test can say is whether the message READS as a message.**
  That is the owner's playtest, like every other thing in this repo whose
  instrument is a picture.

## Revisit trigger

#180 landing. This entry is superseded the moment a disconnect can land
somewhere better than an overlay over a frozen world; the four clauses
above are what that screen has to keep doing, not how it has to look.
