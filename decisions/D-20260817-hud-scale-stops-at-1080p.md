# D-20260817-hud-scale-stops-at-1080p · 2026-08-17 · Accepted

**A bigger window buys battlefield, not a bigger HUD.**

## Decision

`HudLayout.scale_for` is measured against **two** references, not one:

- **below `REFERENCE` (1280x720)** the HUD shrinks with the window, floored
  at `MIN_SCALE` — unchanged, and still `min` of the two ratios so a short
  window cannot push the command panel off the bottom;
- **above it** the HUD is drawn at its **design pixel size** until the
  window reaches `MAGNIFY_ABOVE` (1920x1080), and only then is magnified,
  still clamped at `MAX_SCALE`.

Nothing else in the file changed. The layout, the anchoring, the panel's
own geometry and the player's manual HUD-scale slider (D-063) are all as
they were.

## Rationale

Reported from playtest #30 as issue #90: at a ~1920x1000 client area the
HUD dominates the screen — the command panel alone eats about a third of
the height.

The panel is 264 design units tall, derived from the two stacked button
segments it has to hold (`PANEL_HEIGHT`), which is **36.7% of the 720-high
reference**. `scale_for` was linear in the window, so that fraction was
*preserved at every resolution*: 36.7% at 1280x720, at 1920x1080, at
2560x1440. A player who bought a bigger window got no more of the world,
only bigger chrome — and the same was true of the resource bar and the nav
ring, because scale is one multiplication applied to the whole layer.

The file's stated intent — "the same PHYSICAL size on a big monitor" — is
right about a 4K screen and wrong about the step from 720p to 1080p, which
is usually the *same* monitor with a bigger window on it. Splitting the two
questions is what the second reference does: **fit** is measured against
the size the layout assumes, **magnification** against the size beyond
which pixels really are too small.

Measured, on the reported window (1920x1000):

| | scale | command panel | share of height |
|---|---|---|---|
| before | 1.389 | 367 px | 36.7% |
| after | 1.000 | 264 px | 26.4% |

and across the range (16:9, panel as a share of window height):

| window | before | after |
|---|---|---|
| 1152x648 | 36.7% | 36.7% (unchanged) |
| 1280x720 | 36.7% | 36.7% (unchanged) |
| 1600x900 | 36.7% | 29.3% |
| 1920x1080 | 36.7% | 24.4% |
| 2560x1440 | 36.7% | 24.4% |
| 3840x2160 | 24.4% | 24.4% (unchanged — already at `MAX_SCALE`) |

So the change is confined to exactly the band between the reference and 4K,
which is where players are, and the two ends of the range are untouched.

**Looked at, not only measured** — `docs/playtest/p30-hud-1080-before.png`
and `p30-hud-1080-after.png` are the real client rendered headlessly at
1920x1080 (the software rasteriser, same as `just test-client`, which
hardcodes 1280x720 and therefore renders this fix as a deliberate no-op —
the one resolution where it could show nothing). This is the class of
change the pictures exist for: every number here was healthy for six
milestones.

## Rejected alternatives

- **A sub-linear curve (`sqrt` of the ratio, or a lerp toward 1.0)** — the
  first suggestion in #90. Measured: at the reported window it gives scale
  1.18 and a panel share of 31.1%, still "roughly a third", which is the
  complaint. It also has no size at which a player can say what they are
  getting; a named resolution does.
- **Capping the panel at a fraction of window height and reflowing the
  actions column.** A constant fraction is exactly what linear scale
  already produced, so a cap that binds at 1080p binds at 720p too and
  would shrink the hand-tuned reference layout below 1.0. The cap can only
  ever be the sub-linear rule wearing different arithmetic, at the cost of
  a reflow the column has never needed.
- **Shrinking the design itself** — dropping `BUILD_ACTION_ROWS` from 3 to
  2 would take the panel to 220 units (30.6% at the reference). That row is
  deliberate slack: the worst build category today is 6 buttons, and a
  seventh would silently not show. Removing a safety margin is a separate
  decision from fixing the scale curve, and it is the only lever that
  helps a player actually *on* a 1280x720 window — where, having no pixels
  to give back, this decision does nothing for them at all.
- **Lowering `MAX_SCALE`** — does not bind at 1080p, so it cannot address
  the report.

## Consequences

- **A 16:9 window larger than the reference no longer reproduces the
  reference design space.** That identity was the same statement as the
  bug, and `test_hud_layout.gd` now asserts it only at or below the
  reference. Above it, the design space grows — more room for chips in the
  command panel, and a wider lobby (which shares `_hud_scale`; this can
  only help #91, it does not fix it).
- **The new curve is `<=` the old one at every window size**, which is
  pinned by a test. Nothing can overflow anywhere it used to fit, so no
  anchoring test needed re-deriving. The risk this change does carry is
  legibility rather than layout, and the two existing answers to that —
  `MIN_SCALE`'s floor and the manual slider — are untouched.
- Nothing per-tick was touched: this is client-side pure arithmetic, so
  there is no simulation cost to re-measure.

## Revisit trigger

A player reporting the HUD as too SMALL at 1080p, or a monitor size where
the 24.4% plateau reads wrong. If the panel is still too big at the
reference itself, the lever is the design (`BUILD_ACTION_ROWS`,
`ACTION_BUTTON.y`), not this curve — and that is a decision about what the
panel must hold, not about scaling.
