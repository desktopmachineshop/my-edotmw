# D-20260817 · 2026-08-17 · Accepted — the lobby is scaled to FIT its own content, and whatever it cannot fit still scrolls

**Decision:** the lobby screen's geometry moves out of `client.gd` into
`lobby_layout.gd`, all-static and pure, `hud_layout.gd`'s sibling (D-061).
Three clauses:

1. **Every size is a share of the design rect, not a pixel count.** The
   margin, both column widths, the map preview, the map blurb, the chat
   log, the seat scroll and the help line's wrap width are all fractions
   of `design`, clamped between a floor and a ceiling, re-derived on every
   layout pass. Each fraction is the number it replaces, expressed against
   the 1280x720 window that number was chosen on — so nothing moves at
   that size, and everything else scales.
2. **The lobby scales against its OWN reference height, not the HUD's.**
   `LobbyLayout.DESIGN_HEIGHT` (1000) is how much height the lobby's
   content wants, margins included; `scale_for` divides by that where
   `HudLayout.scale_for` divides by 720. A player's explicit HUD scale
   (D-063) may make the lobby smaller than that fit and may not make it
   bigger.
3. **The page scrolls, as a backstop rather than as the plan.** A root
   `ScrollContainer` under `_lobby_layer` holds the whole screen. Clause 1
   and 2 exist so it is not needed at any window this game asks for; it
   exists so that a window too short for a legible layout costs a
   scrollbar rather than content nobody can reach.

## Rationale

Reported by the owner from playtest #30 (issue #91). On a ~1920x1000
client area the chat panel was clipped mid-panel, GAME SETTINGS crossed
the bottom edge — the "Only the host can change these." caption sitting on
the window border — and the SANDBOX panel was not on screen at all. There
was no scrollbar, so everything below the fold was simply unreachable.

Measured before the fix, on the real lobby in a real tree at that window
size: **the content wanted 896 design pixels of height and was handed
672.** 224 pixels below the fold.

**Three causes, and the third is the one that made the other two bite.**

- Every minimum was a fixed pixel count: 560 and 400 of column width, 198
  of seat scroll, 168 of map preview, 96 of chat log, 32 of blurb, 600 of
  help. A `VBoxContainer` handed less height than its children's combined
  minimum does not shrink them and does not scroll — it overflows, in
  silence.
- Nothing scrolled. The seat list scrolls internally (a lobby seats 20,
  D-018); the page as a whole did not.
- **The design space was smaller than the window and did not grow with
  it.** `_lobby_layer` took the HUD's transform, and `HudLayout.scale_for`
  divides by a 720-tall reference — so a 1000-tall window was laid out
  against 720 design pixels, the same 720 a 1280x720 window gets. There
  was no window size at which the content fit. Making the monitor bigger
  bought the lobby not one design pixel.

**Why the lobby is allowed its own reference where the HUD is not.** The
HUD is an overlay on a world the player reads THROUGH, and 1280x720 is
the window its hand-placed coordinates were tuned against; magnifying it
on a big monitor is the whole point of `scale_for`. The lobby is a
full-screen document with a known amount of content in it, and the useful
question is not "how much bigger than the reference is this window" but
"does it fit". Dividing by `DESIGN_HEIGHT` answers that one: a window at
least 900 tall lays the lobby out at its natural height and scales it up
to fill, so every panel is on screen and the spare pixels go to
legibility. The two layers are never visible at once (`_refresh_lobby`
shows one and hides the other), so they are free to differ.

`DESIGN_HEIGHT` = 1000 is not a taste: `HudLayout.MIN_SCALE` is 0.9, so
900 — the shortest window this decision treats as "must fit" — lays out at
exactly 1000 design pixels whatever this constant says. Choosing anything
larger would claim a fit that the legibility floor cannot deliver.

**Why the constant cannot quietly go stale.** This project's standing
warning is that a documented number with nothing checking it is a number
that drifts (D-065's family; D-106 for the most recent). So
`tests/test_lobby_layout.gd` builds the REAL lobby and fails if the
content it measures no longer fits `DESIGN_HEIGHT`. Two more GAME
SETTINGS rows or a fourth sandbox toggle goes red there, naming the number
to raise, instead of going off the bottom of somebody's screen.

**The lobby is testable, and that is the other half of this entry.**
`client.gd` is native-only (D-014) — but as D-075's amendment already
found for node lifetime, that is true of what it DRAWS. A container's
minimum size is a question about fonts and layout, and a headless
SceneTree answers it. What the client cannot do headless is `_ready()`,
which opens a socket; so the test builds the lobby on an un-started client
and moves its CanvasLayer into the test's own tree. It has to be IN a
tree: off-tree the same measurement comes back **486 instead of 896**,
because theme fonts do not resolve — a test that trusted the off-tree
number would have called this fixed while it was still on screen.

## Rejected alternatives

- **The root `ScrollContainer` alone.** The issue's item 2, and the
  cheapest fix: nothing is unreachable any more. Rejected as the whole
  answer because the content is ~900 design pixels and the design space
  was pinned at 720, so the lobby would scroll on *every* window forever —
  a 1920x1000 screen with obvious room on it would still make the player
  scroll to see the sandbox toggles. A scrollbar that is always there is a
  layout that never fits.
- **Fractional sizes alone.** The issue's items 1 and 3. Measured: it
  recovers about 40 design pixels of the 224, because the tall panel is
  GAME SETTINGS and its height is nine option ROWS, which no fraction
  shrinks. Necessary, nowhere near sufficient.
- **Give GAME SETTINGS its own inner `ScrollContainer`.** Would make the
  right column fit at 720 without touching the scale. Rejected: nested
  scroll regions capture the wheel from the page they sit in, and the
  resulting UX cannot be checked by any instrument this project has —
  which is precisely how the bug being fixed got here.
- **Fix `HudLayout.scale_for` instead** (the #90 direction). A real issue
  and a separate one, being worked in parallel; it is deliberately not
  touched here. It would reduce the pressure and not remove it: at scale
  1.0 the current minimums fit 1920x1000, and any window near the
  1152x648 floor overflows again. This entry's clause 3 is what covers
  that case whatever #90 lands on.
- **Move the lobby's proportions into `hud_layout.gd`.** The issue offered
  this or a sibling. A sibling, both because the two now answer to
  different reference heights and because #90 is editing `hud_layout.gd`
  in another session and a shared file is a merge conflict for no gain.

## Consequences

- `lobby_layout.gd` is new. `client.gd` loses `LOBBY_MARGIN`,
  `LOBBY_RIGHT_COLUMN_WIDTH`, `SEAT_ROW_HEIGHT` and six hardcoded
  `custom_minimum_size` assignments; `_layout_lobby` re-derives all of them
  from `design` on each call, which is also what makes them follow a
  resize.
- The lobby now fits, measured: at 1920x1000 it wants **895** design
  pixels and has **936**. Every window in the test's fitting set (1920x1000,
  1920x1080, 1600x900, 2560x1440, 3440x1440), for both an admin and a
  non-admin client — the non-admin is the taller state, since it also
  carries two "Only the host can change these." captions.
- Windows shorter than 900 (1366x768, and the 1152x648 floor
  `HudLayout.min_window_size` allows) genuinely cannot show the lobby at a
  legible scale, and scroll. The test asserts they do, and that the
  scrollbar reaches the bottom of the content.
- `just lobby-shot` takes a RESOLUTION argument. It was pinned to
  1280x720 — the one size at which this bug does not happen — so the one
  instrument that could have shown it was aimed away from it. The same
  shape as `test-client` aiming its camera at a spawn (D-096) and as
  `gen-terrain-preview` drawing a top-down map with no trees in it (D-108).
- Nothing per-tick, nothing on the wire, nothing on the server. The
  arithmetic runs on build and on resize.

## Revisit trigger

The pin test going red — the lobby has outgrown `DESIGN_HEIGHT` and
something has to give: raise the constant (and accept a smaller lobby on a
given monitor), or move content off the screen. Also: #90 landing a
different `HudLayout.MIN_SCALE`, since `DESIGN_HEIGHT` is chosen against
it — 900 / MIN_SCALE is where the number comes from, and if the floor
moves this constant should be re-derived rather than left.
