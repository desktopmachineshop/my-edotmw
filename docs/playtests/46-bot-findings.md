# Playtest #46 — HUD readability and window-resize layout: bot findings

**Ticket:** [#46](https://github.com/desktopmachineshop/my-edotmw/issues/46) — stays OPEN.
**Run:** 2026-08-27, worktree `ao/my-edotmw-85/playtest-visual-infra`, base `cc2f4c6`.
**Instrument:** `playtest_observe.gd --topic=hud` (new, in this branch), plus the
existing `tests/test_hud_layout.gd`.

## Why this ticket is unusually bot-friendly

`hud_layout.gd` is all-static and pure, on purpose, and its own header says why:
*"the client cannot be tested headless (D-014), but 'does the resource bar reach
the right-hand edge' is arithmetic and does not need a GPU to answer."* So
criterion 2 (nothing overlaps, clips off-screen or becomes unreadable at any
window size) and criterion 3 (anchoring AND scaling both work) are measurable
rather than eyeballable. That is what was done.

## Checklist, classified

| # | criterion | class | status |
|---|---|---|---|
| 1 | every readout correct and live | **mixed** | formatters checked; live values need a match |
| 2 | nothing overlaps / clips / goes unreadable at any size | bot-observable | **no clipping at 12 sizes**; one overlap pair, see below |
| 3 | anchoring AND scaling both work | bot-observable | **confirmed** — the two mechanisms are visibly separate in the numbers |
| 4 | compass matches heading exactly | **human** | `compass_offset` is pure but "exactly" is a look |
| 5 | selection panel correct for every entity type | **human** | needs a match with each thing selected |

## The sweep

`HudLayout.min_window_size()` = **1152x648**; scale clamp **[0.90, 2.00]**;
layout reference **1280x720**; magnification threshold **1920x1080**.

```
window        scale  design       panel%  chrome%  offscreen  chips(cap/collapse)
1280x720      1.000  1280x720      10.0     15.3   none       2/2
1920x1080     1.000  1920x1080      6.7     10.2   none       4/4
2560x1440     1.333  1920x1080      6.7     10.2   none       4/4
3840x2160     2.000  1920x1080      6.7     10.2   none       4/4
1152x648      0.900  1280x720      10.0     15.3   none       2/2
1024x600      0.900  1138x667      10.8     16.5   none       2/2
 800x600      0.900   889x667      10.8     16.5   none       2/2
3440x1440     1.333  2580x1080      6.7     10.2   none       7/7
1280x1024     1.000  1280x1024      7.0     10.7   none       2/2
 900x1600     0.900  1000x1778       4.0      6.2   none       2/2
1920x550      0.900  2133x611       11.8     18.0   none       5/5
 640x480      0.900   711x533       13.5     20.6   none       2/2
```

(The last three rows and `800x600` are below `min_window_size` and cannot occur in
play; they are in the sweep because a layout that only holds for reachable sizes
is a layout nobody has stress-tested.)

**Criterion 2's clipping half passes outright.** Not one of the seven named rects
— resource bar, status, menu button, minimap ring, notice band, command panel,
minimap — leaves the design rect at any of twelve window sizes, including a
21:9 ultrawide, a portrait 900x1600 and a deliberately absurd 1920x550 letterbox.

**Criterion 3 is confirmed, and the numbers show the two mechanisms doing
different jobs.** Scale stays 1.000 from 1280x720 to 1920x1080 and only then
climbs (1.333 at 1440p, clamped 2.000 at 4K), which is
`D-20260817-hud-scale-stops-at-1080p` working: the panel is **10.0% of a 720p
window and 6.7% of a 1080p one**, so a bigger window buys battlefield. Anchoring
is separately visible at 3440x1440, where the design rect goes **2580x1080** —
wider than the reference — and every element still lands inside it. Either
mechanism alone would fail one of those two rows.

## What the sweep found

### The notice band and the minimap ring geometrically overlap, at every size

`compute()` places the refusal-notice band at `y = BAR_HEIGHT + 10 = 48`, height
22, spanning the **full width**; the minimap ring starts at
`y = BAR_HEIGHT + MARGIN = 50`. So the two share a 20-design-unit band down the
right-hand edge, at every window size in the sweep.

**In practice no shipped message reaches it**, and this is reported as a margin
rather than a bug. The notice label is `HORIZONTAL_ALIGNMENT_CENTER` at
`HudTheme.BODY_SIZE` (16), and the longest notice `server.gd` sends is
*"That building cannot train <unit> yet — is it still under construction?"*, on
the order of 610 design units wide. Centred in the narrowest **reachable** design
width (1280, since 1152x648 scales back to the reference) that spans roughly
x 335–945, and the ring begins at x 1054 — about **110 design units of clearance**.

Two reasons it is worth the owner's eye anyway:

- the clearance is not enormous, and it shrinks with the message. A longer
  refusal string, or a unit name longer than the shipped ones, closes it.
- the overlap is *structural* — it is in the rects, so nothing would flag a
  future notice that does collide. The band could as easily sit under the ring's
  bottom edge and be immune.

**Look for it in play by triggering a long refusal** (order a barracks to train
something it cannot, on a 1152x648 window) and seeing whether the tail of the
message goes under the minimap.

### `test_hud_layout.gd`'s train-list guard is red, and it is the guard that is wrong

Reported in full in [#215](https://github.com/desktopmachineshop/my-edotmw/issues/215)
with the rest of the red suite; the short version, because it is this ticket's
territory:

`barracks.produces` is now the **14-archetype union** of all six civs, and the
test compares the chip strip's capacity against that union — 6 at 1600x900, 8 at
1920x1080. But `client.gd:_show_train_chips` resolves each archetype through
`UnitRoster.for_civ_archetype` and drops what the player's civ does not field, so
a player sees at most:

```
gildedreach 6   emberdeep 5   gravesworn 4   stoneblood 4   thornwood 4   windmarch 4
```

**Six against a capacity of six — it fits, with zero margin.** So the failing
test is not currently a player-facing defect. What *is* broken is that the guard
now measures the wrong quantity and will therefore not catch the real thing: one
more archetype for Gildedreach, or one narrower window, makes a train ORDER
unreachable. That is precisely what
`D-20260817-selection-bar-three-columns` was written against — *"When a layout
gets tighter, the question is never 'what still fits' — it is 'what can no longer
be reached'."*

### The chip strip seats only 2 tiles at 720p when a SQUAD is selected

`chip_capacity` with `building_column_in_use = true` (a squad selected, so the
build column is live) is **2 at 1280x720 and 4 at 1920x1080**, against 6 and 8
when a building is selected and the strip takes the build column's width. Two is
the design floor — `HudLayout`'s own comment says *"a capacity of one would be a
strip that pages forever without ever showing anything"* — so this is the design
working, not a fault. It is recorded here because it means **a 720p player pages
through squad chips constantly**, which is a legibility question a picture can
answer and arithmetic cannot.

### Readout formatters are correct

```
clock   0s -> "0:00"    61s -> "1:01"    3661s -> "1:01:01"
n/cap   0/40 -> "0/40 squads"   12/40 -> "12/40 squads"   44/44 -> "44/44 squads"
```

The 44/44 case is worth noting: Gravesworn's `squad_cap_bonus = 4` is live since
#158, so a cap above 40 is reachable in play and the readout handles it. Whether
it *matches the server's refusal* at that cap is a match-time question — the
decision entry says one number feeds both, and criterion 1 is the place to
confirm it.

## Bugs filed

None unique to this ticket. The train-list guard is folded into
[#215](https://github.com/desktopmachineshop/my-edotmw/issues/215) (the red-suite
issue) because its cause is #191's roster union, not the HUD.

## What remains for the owner

1. **Criterion 1 — every readout against reality.** Clock vs wall time, resources
   vs actual stockpile, n/cap vs actual squads, over a few minutes of play. The
   formatters are right; whether they are *fed* right is not checkable here.
   Give the n/cap the Gravesworn case specifically (cap 44).
2. **Criterion 2's legibility half.** No element clips — but "unreadably small"
   is a judgement. The scale floor is 0.90 and a 1152x648 window sits exactly on
   it; `MIN_SCALE` was already raised once from 0.75 after being reported as hard
   to read, so that floor has form.
3. **Resize DURING a match with things selected and the minimap busy** (the
   ticket's step 3). Nothing here exercises the *transition*, only the endpoints.
4. **Criterion 4 — the compass** after several rotations.
5. **Criterion 5 — the selection panel for every entity type**: a squad, a mixed
   selection, each building type, an enemy. This is where the chip-strip paging
   above is worth watching: select a barracks as Gildedreach and confirm all six
   train orders are reachable.
6. **The notice/ring overlap**, per the repro above.

## Tooling added by this pass

`just test-client` now takes a **RESOLUTION** argument (default unchanged at
1280x720). It was pinned to the one size at which a HUD scaling or anchoring
defect is a deliberate no-op — the same trap `just lobby-shot` was fixed for in
#91, and the reason #90 was invisible to it. `just test-client 90 3 1920x1080`
now takes the frame the ticket's step 2 wants.
