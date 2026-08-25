# D-20260823 · The drag shows the line it will form

**Status:** ACCEPTED — the owner's request (2026-08-23): *"the drag draws
battle line should show translucent circles for the unit formation as it
be commanded when you release it. formations need to flex based on this
(tight but long and thin or short and wide or square) — the tightness
just drives the unit closeness rather than exact shape. shape to be
defined by the right click."* **Extends:**
D-20260819-a-drag-draws-the-battle-line, D-058 (formations as data),
D-096's shared-answer rule.

## Two rules, and they are the same rule twice

**1. The preview is the order.** While the right button drags, every
selected squad draws a translucent disc PER MAN at the exact spot that
man will be commanded to. The positions come from `BattleLine.plan`
followed by `Formation.slot_world_offset` — the same two calls the
release sends and the renderer then draws with — never from a second
copy of the arithmetic in `client.gd`. A preview computed separately is
a preview that eventually lies, which is the defect D-096 records about
the building ghost and D-061 records about geometry that lives in
`client.gd` where no test can reach it. `slot_world_offset` is
EXTRACTED from `soldier_transform` rather than written beside it, so
there is still exactly one definition of where a man stands.

**2. Shape is the player's, tightness is the formation's.** A dragged
stroke sets the frontage; the men fill ranks behind it. So a long stroke
is a long thin line, a short one is a deep block, and the sizes between
are square — three shapes from one gesture, with no mode to choose.
A formation's `spacing_scale` may then only change how CLOSE those men
stand, never the shape:

- A width order already outranks a formation's declared `ranks`/`files`
  (`Formation._offset_for`), so a dragged shield wall is as wide as it
  was dragged. That was already true and is now guarded by a test.
- `plan`'s files arithmetic uses the formation's EFFECTIVE spacing
  (`Formation.effective_spacing`, unit spacing × the formation's
  `spacing_scale`) rather than the unit's raw spacing. It did not, and
  the consequence was visible the moment the preview existed: a tight
  formation was dealt the files a LOOSE one would need, so it packed
  short of its own stroke and left a gap at each end. Tighter men fit
  more per metre — that is what tightness means.

## Rejected alternatives

- **Drawing the preview on every visible lattice copy (D-008).** The
  drag stroke itself is drawn on the canonical copy only, and the
  battle-line decision says out loud that a transient input hint is not
  world state. The discs follow the stroke they belong to.
- **A "formation shape" picker beside the drag.** The gesture already
  carries the shape; a picker would be a second way to say the same
  thing, and the two would disagree the first time somebody dragged
  after picking.
- **Previewing with the sim's ground-nudge applied**
  (`Formation.grounded_offset` against real passability). The client
  draws its own soldiers with an empty passability array, so the preview
  matches what the client will actually draw; adding a nudge here would
  make the preview differ from the render, which is the one thing it
  exists not to do.

## Revisit trigger

If a squad's men visibly settle somewhere other than their discs — on
broken ground, or against a building the push-out rule moves them off —
the preview has started lying and the honest fix is to show the
post-push positions, not to soften the claim.
