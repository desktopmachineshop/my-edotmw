**Between M7 and M9, three days of playtest-driven work landed (2026-08-11
to 08-14) that belongs to no numbered milestone.** `just test-unit` is
green at **563 tests** across 37 scripts (measured 2026-08-14);
`test-load` clean at **57.88 µs/squad** (4 bots, the usual ~52 squads —
quote it with the count, as ever). The pieces:

- **Walls, gates, and a walkable wall-top tier (D-076)** — the feature
  D-069 explicitly fenced out of M9 and said needed its own decision.
  Chained single-cell buildings, not edges; the wall-top is a second
  `FlowField` layer with its OWN cell budget (sharing D-040's counter
  would halve ground-pathing throughput on any tick both run); climbing
  is one explicit teleport hop through an access tower's door, which is
  what keeps a squad's tier legal under D-006 (nowhere for a
  partial-climb value to live). Tier-1 squads fight with their own stats
  plus a range bonus and can only be hit by tier-1 or ranged attackers.
  Two standing gaps: **no AI builds or uses walls, so `just ai-ladder`
  cannot exercise any of this feature**, and the geometry/placement UX
  is only proven by playing (it lives in `client.gd`, unreachable from
  GUT).
- **The playtests that closed M7's criterion 14 also earned their keep in
  bugs.** The best one: `_finish_build` consumed ANY builder on
  completion, not just founders — so every gatherer that finished a
  barracks, tower or wall had been silently vanishing since D-031. The
  declared-and-unread defect family, in its over-READ variant; nothing
  fails, the game just quietly loses a rule. Found only by playing.
- **Sandbox mode (D-077)** for dev testing, structurally unable to leak
  into a real match; **leave-to-lobby and no-humans-means-no-server
  (D-075)**; the in-game UI reworked to the reference design; authored
  models for resource nodes and the wall family; tower upgrades.
- **An in-match scoreboard (D-102)**, from the #29 playtest, where the
  absence of one blocked a pass criterion outright: per-player colours
  were fully built, tested for distinctness and drawn consistently, and
  a player could not tell which colour was whose once the lobby closed.
  **That is the "mechanism correct, feature absent" family applied to
  legibility** — nothing failed, and the feature was half-delivered.
  Everything the board needed for IDENTITY was already on the client;
  the half that did not exist was **standing**: elimination has been a
  server-side `print` since D-033 and the wire carried none of it, which
  the client's own defeat screen had recorded correctly for two
  milestones. **The board is also the fog line applied to a menu** —
  army size is derived from what the server already sent (own and ally
  only, D-050), never asked for, so an enemy's total is a dash and there
  is no packet a future caller could leak one from.
- **And the other half of that same criterion, found by the same playtest
  (D-20260817-minimap-squad-colours, #82):** the minimap painted squad
  dots cyan-if-mine and red-otherwise — the two-colour scheme M3 wrote
  when there were no per-player colours to read — so an ALLY, whose army
  D-050's shared vision puts on your minimap and nowhere else, was drawn
  in the enemy tone. **The rule was correct when written and nobody
  re-read it after D-052 changed what it depended on**, which is the
  declared-and-unread family inverted: a grep for uncalled members finds
  none of these, and the building pass eight lines above it in the same
  function had been resolving `colour_of` correctly all along.

**"`client.gd` is unreachable from GUT" is only true of what it DRAWS**
(D-075's 2026-08-16 amendment). Its node LIFETIME needs neither a GPU nor
a window, and reading the claim as covering all of it is how the second
match after a return to the lobby came up with **no terrain at all** for
a whole milestone: `_terrain_root` was built once in `_ready()`, freed by
`_teardown_match()`, and never rebuilt, so every later match parented its
chunk meshes to a null instance. Squads and forests rendered perfectly on
top of nothing, and every number stayed green — the capture verdict's
`terrain=true` is set by the *caller* of `_build_terrain()`, so it says
nothing about whether the function got past its first `add_child`.
`tests/test_return_to_lobby.gd` now instantiates the real script (never
adding it to the tree, so `_ready()` does not run) and plays
match → lobby → match against it. **When a client-side thing is
lifetime rather than pixels, it is testable — try before assuming
otherwise.**

**And GEOMETRY is testable too, which the lobby found out the hard way
(D-20260817-lobby-fits-the-window, #91).** The lobby ran off the bottom of
a 1920x1000 window — chat clipped, GAME SETTINGS on the window border,
SANDBOX not on screen, no scrollbar. Its sizes lived in `client.gd` as
fixed pixels, so nothing covered them; they live in `lobby_layout.gd` now,
as shares of the design rect, and **`LobbyLayout.DESIGN_HEIGHT` is what
the lobby is scaled against** — a screen that is a full-page DOCUMENT is
laid out to fit its own content, where the in-match HUD is magnified
against `HudLayout.REFERENCE`. Sharing the HUD's 720-tall reference is
what pinned the lobby's design space at 720 no matter how big the window
got. Three things worth carrying:

- **A layout test must measure the REAL controls, in a REAL tree.** The
  same lobby measures 486 off-tree and 896 in one, because theme fonts do
  not resolve off-tree — and the off-tree number would have declared the
  bug fixed while it was still on screen. `_ready()` opens a socket, so the
  test takes the lobby's CanvasLayer out of an un-started client and adds
  *that* to the tree.
- **A constant that describes content needs a test that measures the
  content.** `DESIGN_HEIGHT` is pinned by building the lobby and comparing,
  so adding two settings rows goes red there rather than off a screen.
- **`just lobby-shot` takes a RESOLUTION now.** It was pinned to 1280x720,
  the one size at which this bug does not happen, so the single instrument
  that could have caught it was aimed away from it — the `test-client`
  points-at-a-spawn lesson again.
