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

- **And the leave-to-lobby path was a dead end in the one session a solo
  player uses** (D-20260817-an-ai-never-holds-the-lobby, #92, from
  playtest #30). `server.gd`'s `_seat_ai` registered every command-line AI
  (`--ai=N`: `quick-test`, `run-server AI=3`) through `MatchState.
  add_player` — which seats a **human**, and a human seat with nobody yet
  in the chair takes `admin_player`. So all three AI seats read `human` in
  the lobby, **the first AI held the Admin badge**, and after ESC → leave
  to lobby the human's start button read "Waiting for host" forever.
  Three more consequences rode on the same mislabel, none of them visible
  to any check: the next match would have rebuilt **no AI brains at all**
  (`_on_match_started` only re-seats `kind == "ai"`, and the seat still
  counts for elimination), and the seat's civ overwrote the brain's, which
  is the AI-fields-another-civ's-troops defect reachable through a second
  door. **This is the declared-and-misread variant of the family**: `kind`
  is read everywhere — wire, client, lobby rules, match start — and one of
  the two writers simply set it wrong, so nothing failed. `add_ai` had
  been correct the whole time, and every lobby test went through it. There
  is one seating function now, two doors onto it, and admin is claimable
  only by a human seat — which also repairs a session already running with
  an AI in the chair.

- **And selection kept its dead** (D-20260817-selection-drops-the-dead,
  #88, from playtest P03 step 6). A wiped squad stayed in `_selected` and
  in any control group it belonged to, so recalling the group read
  "2 squads / 0 soldiers" with a chip at 0/36. `ClientState` has pruned a
  wiped squad out of `squads` since M1 under a comment naming this exact
  consequence — *"the GUI offers a dead squad for selection"* — and
  `client.gd` never read it. **The declared-and-unread family with the
  READER missing rather than the writer**, and invisible to every counter
  because nothing was wrong: the order paths already refuse a squad the
  client does not own, and the server refuses again. The selection and
  every stored group are filtered against `ClientState.owns` once per
  frame now, through a pure `SelectionRoster` — one writer rather than a
  filter at each of eight readers, since the defect *was* a reader nobody
  wrote.

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
**And one from playtest #30 that is about a NUMBER being a fraction
(D-20260817-hud-scale-stops-at-1080p, #90): the HUD dominated the screen
at 1080p, and had done at every resolution equally.** `HudLayout.scale_for`
magnified the HUD linearly with the window, so every element kept a
CONSTANT SHARE of it: the command panel is 36.7% of the 720-high reference
by construction, and was still 36.7% at 1920x1080 and at 2560x1440. A
player who bought a bigger window got no more battlefield, only bigger
chrome. Magnification is measured against 1920x1080 now instead of the
1280x720 layout reference — fit and magnification are different questions
and were sharing one ratio — which takes the panel to 24.4% at 1080p and
leaves the reference window and 4K untouched. **The instrument that shows
it is a picture at 1080p** (`docs/playtest/p30-hud-1080-{before,after}.png`):
`just test-client` hardcodes 1280x720, which is the one resolution where
this fix is a deliberate no-op, and in design units the panel is 264 at
every window size — the bug is only visible in real pixels DIVIDED BY the
window, which is what the new test measures.

**And the same playtest's second half, which is a layout lesson rather than
a fog or colour one (D-20260817-selection-bar-three-columns):** the command
panel was 264 design units tall because it paid for the title stack AND the
formation grid AND the build grid, one under the other, when it only ever
had to be as tall as the WORST of the three. Two grids a player uses at
different moments were stacked because the break between "Stop" and "Build
Barracks" was drawn as a horizontal divider; as a vertical RULE between two
columns the same break costs no height at all. Three columns — selection,
orders, build — with 26-unit buttons put the bar at **72 units, 7% of a
1080p window against the 36.7% it started at**.

**The trap in it is worth more than the layout.** A one-row chip strip
seats four tiles and a barracks trains SIX — and those tiles are the train
ORDERS, not a picture of them (D-061). So the first short version made two
units unbuildable at some window sizes: a cap that hides a CONTROL, this
project's oldest defect family, arriving disguised as a spacing tweak. The
strip therefore reserves its two-chip minimum BEFORE the buttons take their
share, takes the build column's width whenever the selection cannot build,
and its overflow chip PAGES rather than merely reporting. **When a layout
gets tighter, the question is never "what still fits" — it is "what can no
longer be reached".**

**And a client that lost its server said nothing at all
(D-20260827-a-client-with-no-server-says-so, #162, from launching
playtest P09).** The window looked frozen. It was not: the server had
shut down — correctly, per D-075's "no humans, no server" — and the
client kept its window, kept ~44% of a core and kept drawing a world
that could no longer change. `client: disconnected` went to stdout and
nowhere a player can see.

Three things worth carrying, none of them about netcode:

- **D-075 was careful about the SERVER half of this lifecycle and the
  client half was never written.** The ordinary shape: a rule absent
  rather than wrong, so nothing fails and the symptom is reported as a
  hang. It is one overlay now, and the backdrop TAKES the mouse — that
  is the "sane state" half, because the client sends orders from about
  twenty `_peer.send` sites and one backdrop is one place where twenty
  guards would be the same rule written twenty times.
- **The match is deliberately NOT torn down.** `_teardown_match()` frees
  the terrain, the squads and the buildings, so a player who has just
  lost the server would get a black screen instead of the last thing
  that happened. The overlay therefore has to OUTLIVE a teardown — which
  is asserted, because a thing `_ready` built once being freed by
  `_teardown_match` is exactly how the second match came up with no
  ground for a milestone.
- **The two tests that matter are the CALLER scans.** Everything else in
  `tests/test_connection_lost.gd` drives `_on_connection_lost()`
  directly and would pass on a client that never shows anything; the
  scans assert `_ready` builds the overlay and the disconnect branch
  calls the handler. Same rule as D-106's, and it is the third time
  `client.gd`'s LIFETIME has had to be shown testable — instantiated,
  never added to the tree.

Deliberately small: #180 (the pre-lobby main menu) names #162 as its
sibling and is where a disconnect should eventually land, so this is one
function with one caller for that ticket to replace. **#162's second
defect, the blocking terrain build, is already fixed** by
`D-20260818-terrain-builds-a-slice-at-a-time` (#106) and is not
re-addressed here.

**And a gate did not know its owner had allies
(#210, 2026-08-28).** An auto-mode gate opened for its OWNER's squads and
for nobody else, so a teammate stood at a closed gate and walked round
the wall — or could not get through at all if the wall was closed.
`server._update_auto_gates` compared owner ids where `SquadSim.are_allied`
is what the rest of the simulation asks: `combat.gd` calls it in five
places, and `client.gd` and `ai_player.gd` call it too.

Third of the same family recorded on this page, and the tell is identical
every time — **a raw owner comparison sitting beside a codebase that
compares teams everywhere else, with nothing failing**:

- **#83** — `ai_player.gd` held zero references to alliance, so its
  targeting read "not mine" as "hostile" and marched an army onto a
  teammate's town centre.
- **#82** — the minimap painted squads cyan-if-mine and red-otherwise, a
  rule that was correct when written and never re-read after D-052.
- **#210** — a gate rule written *after* teams existed that still asks the
  pre-teams question.

Two things worth carrying:

- **It is an omission, not a rejected alternative.** D-076 specifies
  *"auto-open when the owner's own squads are near"* and mentions teams
  nowhere; D-050 predates it. The question was never asked, which is why
  no decision entry records an answer to it.
- **Nothing could have gone red either way.** `test_wall_top.gd` and
  `test_wall_run.gd` are thorough about the tier rules, the climb, the
  run geometry and the seam — 29 tests — and **neither contains the word
  `gate`**; `test_buildings.gd` round-trips `set_gate_open` mechanically
  and never touches `_update_auto_gates`. `tests/test_auto_gate.gd` is
  the file that did not exist, and it carries the two controls that keep
  the fix honest: an enemy must still be shut out, and team 0 is not a
  team (D-050) — which is the configuration every AI fixture in the
  estate sits in (#119), so getting it wrong would be invisible to `just
  ai-ladder`.

Deliberately unchanged, both named in the issue as considered positions
rather than oversights: climbing a wall tower is not ownership-gated
(D-076 argues for it — *"a wall's tier-1 top is a contestable
objective"*), and an OPEN gate is open to everyone standing in it, so an
enemy can follow a friendly squad through.
**And a player who quit could stall a match for ever
(D-20260828-leaving-a-match-leaves-nothing-behind, #292 and #318, which
turned out to be one defect).** A disconnect wiped the abandoned ARMY and
left the BUILDINGS standing — and elimination needs both gone — so a
quitter stayed "active", `_check_victory` never fired, and a 1v1 somebody
rage-quit ran to the time cap. The remaining player had no opponent and
no way to win: only a chore, marching across the map to raze an
undefended base before the game would end.

**Nothing failed, because both halves were correct on their own.** D-033
said the wipe is the CAUSE of defeat and the ordinary rule notices the
effect, so "defeated" keeps one definition — and `server.gd`'s comment
named that rule as "no living squads". It stopped being that when
`D-20260823-the-opening-is-a-crew-and-a-general` added the buildings
clause, for the unrelated and correct reason that a crew is consumed by
the town hall it founds. The wipe simply stopped wiping enough, and the
comment asserting the guarantee stayed exactly where it was.

Three things worth carrying:

- **A comment that names another file's rule is a claim about that
  file.** This one was wrong for a whole milestone and is what made the
  defect survive being read — the D-065 family again. There is a test
  now that fails if the old wording comes back.
- **`BuildingSim` had no per-player wipe AT ALL** — no
  `eliminate_player`, no raze-all, nothing. The sibling of a function is
  a good place to look when a rule gains a second half.
- **Observed RED before the fix, all eleven tests**, reporting the
  issue's own symptom. That is the strongest form of this project's
  observed-to-fail rule and it was available because the bug arrived
  with a repro. Each rule was then perturbed individually afterwards,
  because "everything was red before" does not say which test guards
  which rule.

**`test-load` and `ai-ladder` were quietly wrong in the same way** — a
run where a client drops mid-match reported a draw at the cap that was
not one. Neither harness drops clients deliberately, so no recorded
figure is known to be affected; worth knowing before trusting an old run
whose log shows a disconnect.

