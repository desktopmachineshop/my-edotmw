# D-20260819 · A drag draws the battle line

**Status:** ACCEPTED — workstream 8 of
D-20260818-battle-quality-outranks-player-count, and the gesture half of
exit criterion 5. **Drives:** D-20260819-facing-and-width-are-orders'
opcodes, exactly as that entry said it would. **Relates to:** D-034
(ctrl still means attack-move), D-076 (the wall drag-build is the same
press-drag-release grammar on the left button).

## Decision

Right-press somewhere, drag, release: the SELECTION forms a battle line
along the dragged stroke — position, facing and width in one motion,
several squads at once. A release inside `DRAG_ORDER_THRESHOLD_PX` (12)
is exactly yesterday's click (order at the press point; Alt still means
face). Nothing new crosses the wire: the gesture compiles into the
move/attack-move, facing and width orders workstream 5 built.

The arithmetic lives in **`battle_line.gd`** — all-static and pure, the
`hud_layout.gd` family, because client geometry that only lives inside
`client.gd` is client geometry nobody can test (the D-061 lesson,
written as code):

- The stroke is split into one segment per selected squad; each squad's
  destination is its segment's midpoint, its files are
  `segment_length / spacing` (what fits shoulder to shoulder), and its
  facing is the stroke's PERPENDICULAR, signed to point AWAY from the
  selection's current centroid — troops walk up and face onward, which
  is what the gesture means everywhere it exists.
- **Squads are assigned segments by their projection along the
  stroke**, so lines do not cross while forming — the leftmost squad
  takes the leftmost segment.
- Ctrl-drag issues attack-moves instead of moves; everything else is
  identical.

A thin ground stroke is drawn while dragging (canonical copy only — a
transient input hint, not world state; the lattice-copy rule is about
things that EXIST).

## Rejected alternatives

- **A "form line" opcode.** The server would then own a formation
  planner the client cannot preview and the player cannot partially
  override; compiling to existing per-squad orders keeps the authority
  boundary exactly where D-002 put it.
- **Facing toward the drag's second half** (RTW's subtlety where drag
  direction flips facing). One convention — away from where the troops
  currently stand — is predictable and needs no tutorial.

## Revisit trigger

If playtests want unequal segments (wide squads taking more of the
stroke), `BattleLine.plan` gains a strength-weighted split — pure
function, no wire change. If the preview stroke needs to survive on
lattice copies (reported as the line vanishing at a seam), it joins the
LatticeCopies machinery like every drawn thing before it.
