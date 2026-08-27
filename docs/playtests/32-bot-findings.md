# Playtest #32 — torus seamlessness: bot findings

**Ticket:** [#32](https://github.com/desktopmachineshop/my-edotmw/issues/32) — stays OPEN.
**Run:** 2026-08-27, worktree `ao/my-edotmw-85/playtest-visual-infra`, base `cc2f4c6`.
**Instruments:** `playtest_observe.gd --topic=seam` and `just gen-seam-shot` —
both new in this branch, because nothing in the estate could frame a seam.

## Why a new instrument was needed

Three rendered instruments exist and **all three are deliberately framed on
something else**: `test-client` points its camera at a player's spawn,
`gen-terrain-shot` finds the longest run of passability boundary on the map, and
`gen-forest-preview` finds the densest wood. A seam is exactly as likely to
appear in any of them as any other cell — which is to say almost never, and never
on purpose.

That is this repo's own most-repeated lesson about instruments, and it is written
down three times already: cliffs were invisible to `test-client` because a spawn
is walkable by construction (D-097), forest interiors because a spawn is open
ground (D-108), and the prop-fog edge because the map ladder moved the camera
inside the player's own vision (`docs/status/ground-fog.md`). **When a rendered
check has to see something specific, frame it on purpose.**

`just gen-seam-shot SEAM HEIGHT` does that: `q` (the width wrap), `r` (the height
wrap) or `corner` (both at once). It draws terrain over all nine lattice copies as
`client.gd` does, then places two squads — one **on** the wrap line, one clear of
it as a control — through the client's own three-call copy pipeline
(`RenderCull.visible_offsets_of_extent` → `LatticeCopies.draw`), so a squad
straddling the seam is drawn exactly where the game would draw it.

## Checklist, classified

| # | criterion | class | status |
|---|---|---|---|
| 1 | no visible edge, hairline, texture jump or lighting change on either seam | **mixed** (picture) | three frames taken, **nothing visible on either seam** |
| 2 | armies never vanish, pop or duplicate at the seam | bot-observable | mechanism confirmed; a seam squad reports 3-4 copies and is drawn at all of them |
| 3 | minimap view rect and blips wrap correctly | bot-observable | **confirmed** |
| 4 | orders across the seam path the SHORT way | bot-observable | **confirmed, both axes** |
| 5 | selection works on units straddling the seam | bot-observable | mechanism confirmed by code + existing tests |

## What was measured

Shipped default map: **168 x 194 = 32,592 cells**, `hex_size` 1.00, lattice steps
`(290.98, 0, 0)` and `(168.01, 0, 291.0)`.

### Criterion 4 — orders take the short way. Confirmed on both axes.

Straight torus distance, which is what `TorusSpace` — the one definition every
mover reads (D-008) — answers:

```
q-wrap  (1, 4)   -> (166, 4)     distance 3 cells   (the long way is about 165)
r-wrap  (10, 1)  -> (10, 192)    distance 3 cells   (the long way is about 191)
```

But a distance is not a route. So a real `FlowField` was solved to a destination
on the far side of each seam and **walked**, because walking the field IS the
route a squad takes:

```
q seam   (2, 4)  -> (164, 5)     20 steps   (torus distance 6, long way ~162)
r seam   (20, 2) -> (19, 191)    13 steps   (torus distance 6, long way ~188)
```

Both reachable, both the short way round. The step counts exceed the straight
distance because the shipped map has water and steep ground between those cells —
that is a route going round a lake, not round the world. The number that matters
is 20 against 162.

### Criterion 3 — the minimap wraps. Confirmed.

`MinimapPaint.footprint` is the one definition of what the minimap paints. A
4-cell building placed at cell `(0, 6)` — straddling the q seam by construction —
comes back as **16 cells, x from 0 to 167, none outside the image**, with both
edges present. A footprint that did not wrap would either clip to x ≥ 0 or return
negative coordinates; it does neither.

`tests/test_minimap_paint.gd::test_a_mark_at_the_seam_wraps` already guards this
and passes. The measurement here is against the *shipped* map rather than a
fixture.

### Criterion 2 — the mechanism, and why the picture is still the check

Nine lattice offsets per entity, as D-035 requires. The mechanism that makes
criterion 2 hold is `D-20260818-entities-are-drawn-at-every-visible-copy`, and it
is well covered: `tests/test_lattice_copies.gd` has 11 tests including *"a view
holding two copies of the same ground is told about both"*, *"a squad is drawn at
every copy it is given"*, *"a squad with no visible copy is drawn nowhere"* and
*"the client draws entities at every copy rather than choosing one"*. All pass.

`client.gd:1167` confirms the shape at the call site: `visible_offsets_of_extent`
is *"purely the DERIVATION GATE (D-045)"* now — an empty list means don't derive,
and it no longer decides *where* anything goes, so a cull mistake can fail to
draw but can no longer move a squad.

So criterion 2 is structurally sound. **What no test can say is whether it looks
right**, which is why the shot exists and why the ticket is a playtest.

### Criterion 5 — selection at the seam

`client.gd` records what the renderer actually drew (`unit.set_lattice_offsets(drawn)`,
line 1169) and the pick ranks across that list rather than reading `node.position`
— the fix `docs/status/lattice-copies.md` describes: *"A squad on two visible
copies has two screen positions and both are aimable."* The selection radius comes
from `Formation.footprint` at the squad's real strength, so a wide formation is a
wide click target.

**There is no test that clicks a squad straddling the seam.**
`tests/test_selection_pick.gd` has 11 tests and none mentions a seam or a wrap;
`tests/test_lattice_copies.gd` covers what gets *drawn* at every copy but not what
gets *picked*. The mechanism is right and the coverage stops one step short. Not
filed as a defect — it is a coverage gap in a criterion the ticket assigns to a
human anyway — but worth knowing before trusting a green suite on this point.

## The frames

Three, all at 1400x900, all in the shipping `WorldLook` rig, all on the shipped
default map. Taken on **Intel Iris Xe** through `forward_plus` — note that
`LIBGL_ALWAYS_SOFTWARE=1` does not reach the Intel driver on Windows, so these
are hardware frames rather than llvmpipe ones. That does not matter for a
correctness picture; it is recorded because the recipe's own comment claims
software rasterisation.

| file (committed copy) | seam | focus cell | copies reported |
|---|---|---|---|
| `docs/playtest/p40-seam-q.png` | width wrap | (0, 36) | seam squad 3, control 3 |
| `docs/playtest/p40-seam-r.png` | height wrap | (22, 0) | seam squad **4**, control 3 |
| `docs/playtest/p40-seam-corner.png` | both | (0, 0) | seam squad **4**, control 4 |

### Criterion 1 — nothing is visible on either seam

**The seam cannot be located by eye in any of the three frames.** In each shot
the wrap line passes through the squads at the centre of the picture, and the
ground across it shows no hairline, no geometry crack, no colour step, no texture
jump and no lighting change. Biome blending runs continuously across the join,
the shoreline is organic rather than scalloped along hex edges, and there is no
sign of the ruler-straight bright seam that torn UV derivatives produce (the
defect `shaders/terrain.gdshader` uses explicit gradients to avoid).

That is a real result rather than an absence of evidence, because the framing is
deliberate: `_seam_focus()` walks the whole wrap line and picks the cell with the
most biome variety within three cells, so each shot is aimed at the busiest
stretch of that seam — the place a discontinuity has the most to be discontinuous
in. A featureless stretch of open water would have proved nothing.

### Criterion 2 — nothing vanished

Every squad placed was drawn. `RenderCull.visible_offsets_of_extent` reported
**3 or 4 on-screen lattice copies** for each, and `LatticeCopies.draw` drew all
of them; no frame shows a squad missing, and none shows a second copy standing in
frame where there should be one. This is the D-20260818 mechanism doing its job
on the shipped map rather than on a fixture.

What a still cannot show is a **pop** — a squad that vanishes for one frame as it
crosses. That is motion, and it stays with the owner.

### One thing the frames raise, which belongs to #48 rather than here

`docs/playtest/p40-seam-corner.png` shows **dozens of small grey quads scattered across
gently rolling green ground**, most of them detached-looking rather than attached
to any visible wall. In `docs/playtest/p40-seam-r.png` the same geometry reads correctly
— clear vertical rock faces down the coast and up the slopes, walls rather than
holes, which is D-097 working.

The difference is the ground under them: on a steep coast the skirt has a wall to
belong to, and on gentle terrain it appears to be a shard lying on the grass.
Carried into `docs/playtests/48-bot-findings.md` with the terrain shot, since it
is a terrain-rendering question and not a seam one.

### An instrument caveat, so nobody reads it as a defect

`playtest_seam_shot.gd` places its men by sampling `TerrainChunk.height_at` and
**does not apply the passability clamp the real client applies**
(`D-20260818-a-soldier-stands-where-his-squad-could-walk`). In `p40-seam-q.png` and
`p40-seam-r.png` the focus cell is coastal and some men therefore stand in shallow
water. That is the preview's simplification, not the game's behaviour.

## Bugs filed

None from this ticket. The seam arithmetic is correct everywhere it was measured.

## What remains for the owner

**Criterion 1 in full, and the eyeball halves of 2 and 5.** Specifically:

1. Pan continuously across both seams at play zoom and at a low angle. Watch
   geometry, texture, biome colour, cliffs, trees and ground cover across the
   join. `just gen-seam-shot q` / `r` / `corner` gives you the same three framings
   to compare against, in the shipping lighting rig.
2. March an army across a seam while watching it; then watch a distant army near
   a seam while panning. The failure this hunts is a pop or a duplicate, and both
   are motion artefacts a still cannot show.
3. Box-select a group straddling the seam (criterion 5's real content).
4. Watch the minimap view rectangle — the arithmetic above covers *blips*, not
   the **view rect**, which is drawn from the camera and was not measured.

## Reproducing the frames

```
just gen-seam-shot q        # artifacts/seam-q.png
just gen-seam-shot r        # artifacts/seam-r.png
just gen-seam-shot corner   # artifacts/seam-corner.png
```

`HEIGHT` is the second argument (default 16) if you want the eye lower or higher.
The PNGs are not committed; the recipe and the scene are.
