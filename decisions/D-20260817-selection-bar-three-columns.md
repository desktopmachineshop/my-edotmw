# D-20260817-selection-bar-three-columns · 2026-08-17 · Accepted

**The selection bar is three columns and 72 units tall, not two stacked
grids and 264.**

## Decision

The command panel's contents are three columns, left to right:

1. **selection** — what is selected, its health, and what it is producing;
2. **orders** — formation and movement (`Client._action_buttons`);
3. **build** — the build menu (`Client._build_action_buttons`).

The panel's height is the **tallest** of them, never their sum
(`PANEL_HEIGHT` is written as that `max`). With the two action grids side
by side, 26-unit buttons, one row of chips and the selection column laid
out as a two-sub-column TABLE rather than one tall stack, that is **72
units**, against 146 for the three-column layout with 38-unit buttons and
264 for the stacked one it replaces.

Four things came with it, each because the short bar forced it:

- **Button width is a function of the panel** (`action_button_size`),
  clamped between 96 and 200 units. Two grids side by side cannot share
  one width across a 1280-to-1920 design space.
- **A button is one line, clipped, with the full text as its tooltip.** At
  26 units there is no second line, so a build button reads
  "Barracks · 80 wood" rather than stacking the cost underneath.
- **The chip strip takes the build column's width when the selection
  cannot build.** That is exactly when a BUILDING is selected, which is
  exactly when the strip is holding train tiles.
- **The overflow chip is a PAGER**, not a label. `+2 more` advances a page
  and wraps.

## Rationale

Requested during the playtest that produced #90: after the scale fix
(D-20260817-hud-scale-stops-at-1080p) the bar was "much better", then
"even less room", then a specific structure — build right, formation and
movement middle, selection left — then "50% shorter".

The height was never the button rows' fault. The panel was paying for
the title stack AND the commands grid AND the build grid, one under the
other, when it only ever had to be tall enough for the worst of the
three. Two grids that a player uses at different moments were stacked
because the visual break between "Stop" and "Build Barracks" was made
with a horizontal divider; the same break costs no height at all as a
vertical rule between two columns.

| | panel | share of a 1920x1000 window |
|---|---|---|
| stacked, before #90 | 264 | 36.7% (367 px, magnified) |
| stacked, after the scale fix | 264 | 26.4% |
| three columns, 38-unit buttons | 146 | 14.6% |
| three columns, 26-unit buttons | **72** | **7.2%** |

`docs/playtest/p30-hud-bar-short.png` is the real client at 1920x1080 with
a town centre selected — the whole bar, including its production readout
and train tile, in one strip along the bottom.

## The constraint that shaped it, and nearly broke it

**A barracks trains six units, and those train tiles ARE the train
orders** (`Client._show_train_chips`, D-061's "two buttons for Gatherers"
fix). A one-row chip strip seats four or five. So the short bar's first
version made two units unbuildable at some window sizes — a cap that
hides a CONTROL, which is this project's oldest defect family, arriving
by way of a layout tweak.

Three things answer it, and the test suite found all three:

- the strip takes the build column's width for a building (above), which
  seats all six from 1600x900 up;
- below that the pager reaches the rest, one click away;
- and `actions_column_width` reserves the strip's two-chip minimum
  **before** the buttons take their share, because a strip with one slot
  would spend it on the pager and page forever. On a panel too narrow for
  both, the buttons are what gets cramped.

`test_hud_layout.gd` asserts the first against the shipped `produces`
lists rather than a remembered number, so a civ that gains a seventh
trainable unit fails there rather than in a match.

## Rejected alternatives

- **Keeping the per-column captions** ("ORDERS", "BUILD"). They cost 18
  units of a 72-unit bar — a quarter of it. The vertical rules and the
  buttons' own words carry the distinction instead. This is the one thing
  here that is purely a judgement call, and it is a one-constant revert
  (`ACTIONS_Y`) if the bar reads as ambiguous in play.
- **Shrinking the design's font sizes instead.** The height came from
  stacking, not from type; scaling type down would have made a shorter bar
  that is also harder to read, and the manual HUD scale slider (D-063)
  already exists for players who want everything smaller.
- **Dropping `BUILD_ACTION_ROWS` from 3 to 2 within the stacked layout**
  (the cheap version considered under #90). It saves 44 units of 264 and
  spends the build grid's slack row to do it.
- **A scrollable chip strip.** More machinery than a pager for a case that
  only arises below 1600x900.

## Consequences

- `ACTION_BUTTON`, `ACTIONS_COLUMN_WIDTH`, `ACTION_CONTROL_ROWS`,
  `BUILD_ACTION_ROWS`, `BUILD_DIVIDER_Y`, `BUILD_CAPTION_Y`,
  `BUILD_ACTIONS_Y`, `actions_column_rect`, `build_slot` and
  `build_divider_rect` are gone. `action_slot` now takes the button size
  and serves both grids: side by side they are the same grid in different
  columns, and two identical bodies differing by a start Y is how the
  build segment's row count and the panel's height drifted apart before.
- Both button pools are sized from the same `ACTION_ROWS × ACTION_COLUMNS`
  grid — six slots each, against a commands worst case of five and a build
  worst case of four.
- The selection column is wider (288 units, was 172) because the height it
  gave up had to go somewhere, and width is what this panel has most of.
- Labels in that column are clipped with an ellipsis. Found by looking at
  the render, not by a test: "Training Gatherers — 12s" drew straight
  across the first chip, because a Godot `Label` does not clip unless told
  to and its box had just become a third as wide.

## Amendment, 2026-08-17: the overlap the short bar shipped with

Found by playing it: with six squads selected, six chips drew straight
across the formation buttons.

`_chip_strip_rect` was computed in `Client._layout_chips`, which runs on a
RESIZE. That was correct for as long as the strip's width was a function of
the WINDOW alone — and this decision made it a function of the SELECTION as
well (the strip takes the build column when nothing selected can build).
The panel's last resize had nothing selected, so every chip count was
measured against the wide strip and drawn into the orders column.

**The lesson is not "call the layout function more often".** It is that
widening the inputs of a cached value silently invalidates the schedule
that cached it, and nothing about the change looks like a caching change.
The same shape as the fourth entry in D-100's family: a value that was
right when written, and that nobody re-read after its dependencies grew.

Three parts to the fix:

- both chip fills re-measure the strip themselves, so the rect cannot be
  older than the list it is measuring;
- the squad branch sets its action lists BEFORE filling chips, because the
  strip's width depends on whether the build column has anything in it —
  filling first measured against the *previous* selection's build list;
- and `chip_collapse_at` collapses a per-squad list to one chip per
  ARCHETYPE as soon as it stops fitting, rather than paging. Six identical
  "Gatherers 5/5" tiles were never worth the room: "Gatherers x6" with
  their combined strength is the same fact in one chip, and the collapse
  rule already existed — it was capped at a legibility threshold of 8 set
  when the strip was four rows deep.

The guard is a SOURCE SCAN (`test_hud_layout.gd`), the same shape
`test_terrain_fog.gd` uses and for the same reason: the rule lives in
`client.gd`, which needs a GPU, and every other check in the file passes
while the client measures a rect it laid out a minute ago.

## Revisit trigger

A player unable to tell the orders column from the build column at a
glance (the captions come back, at 18 units), or a building whose train
list needs paging on a window they actually play at.
