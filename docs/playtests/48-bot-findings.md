# Playtest #48 — terrain and environment visuals: bot findings

**Ticket:** [#48](https://github.com/desktopmachineshop/my-edotmw/issues/48) — stays OPEN.
**Run:** 2026-08-27, worktree `ao/my-edotmw-85/playtest-visual-infra`, base `cc2f4c6`.
**Frames:** `docs/playtest/p40-terrain-cliffs.png`, `terrain-preview.png`, `forest-godot.png`,
`forest-godot-squad.png`, `cover-godot.png`, and the three
`p40-seam-{q,r,corner}.png` from #32.
**Numbers:** `just gen-terrain-preview` and `playtest_observe.gd --topic=terrain`.

## Checklist, classified

| # | criterion | class | status |
|---|---|---|---|
| 1 | no honeycomb read at any zoom | bot-observable (picture) | **passes** in every frame taken |
| 2 | shorelines and biome edges feathered off-lattice | **mixed** | colour feathering passes; **cliff geometry is lattice-stepped** — see below |
| 3 | cliffs read as walls, not holes | bot-observable (picture) | **passes** where there is a wall; see the foreshortening note |
| 4 | no texture seams, no floating or buried armies | **mixed** | no seams; the army half needs a match |
| 5 | forests and cover pass the eyeball test with units in them | bot-observable (picture) | **passes** |

## The shipped map, measured

`just gen-terrain-preview` on `maps/default.tres`:

```
168x194 cells, chunk size 16
16.0% water
7515 of 32592 cells impassable (23.1%)
5483 cliff faces drawn at passability boundaries
5559 resource nodes — 1939 food, 3435 wood, 48 gold, 137 stone
20043 of 25077 walkable cells are open ground (79.9%)
forest biome 4311 cells, 1891 hold a node (43.9% wooded)
143 chunks (11x13 grid), 250076 verts, 206518 tris, built in 19821.6 ms
```

The resource figures match what `docs/status/forests.md` records after #94's
0.60 wood scaling (79.9% open ground against its 79.3%, 43.9% wooded against its
43.9%) — so nothing has drifted there.

**5483 cliff faces** is the number to carry forward. `docs/status/terrain.md`
records **363** for the superseded rule and explicitly says to re-read it off the
recipe rather than quote it; this is that re-read.
`D-20260826-passable-means-flat-enough-to-cross` is what moved it — blocking on
steepness rather than height produces far more boundary, which is the rule
working.

**Meshing is 19.8 s** for the shipped map. That is inside the owner's accepted
30-second budget for the sliced loading bar (#106) but it is most of it, and it
is worth knowing that the budget is 60% spent on the default map before anyone
picks Huge.

## Criterion 1 — no honeycomb. Passes.

`p40-terrain-cliffs.png` (framed on the longest run of passability boundary, low angle,
shipping rig) and all three seam frames show continuous ground: biome colours
blend across cell boundaries with no stepping, the sand-to-water contour is
organic rather than running along hex edges, and there is **no ruler-straight
bright seam** anywhere — the torn-derivative defect `shaders/terrain.gdshader`
uses explicit gradients to avoid (criterion 4's first half).

D-096's blend, D-105's warp and the centre-bleed are all doing their job in the
colour channel.

## Criterion 2 — the colour is feathered; the CLIFF GEOMETRY is not

This is the one thing in this ticket that a picture argues about and no number
reports.

In `p40-terrain-cliffs.png`, along the inlet running down the right of the frame, the
rock faces form a **regular sawtooth of near-identical grey wedges** — an
unmistakable hex staircase. The *colour* shoreline beside it is soft and
organic. So criterion 2 is half-passed: D-096 feathered the paint and the
passability boundary is still exactly on the lattice, and where that boundary is
tall enough to skirt, the lattice becomes visible again as geometry.

That is not a bug in the sense of something being broken — D-097 draws one face
per stepped edge and that is the truthful drawing — but it is precisely what
criterion 2 asks a human to judge, and the frame is the evidence.

## Criterion 3 — cliffs read as walls, and the "shards" are foreshortening

`p40-terrain-cliffs.png` and `p40-seam-r.png` both show clear vertical rock faces down coasts
and up slopes. They read as **walls, not holes** — D-086's ~27-degree normal tilt
is doing what it was added for; nothing renders at the near-black that made
mountain walls look like holes cut in the world.

**A first reading of `p40-seam-corner.png` was wrong and is worth recording as a
correction.** That frame shows dozens of small grey quads apparently lying
detached on gently rolling green, and the obvious hypothesis was isolated
one-cell blocked pockets each drawing a lonely skirt. Measured, that is not what
they are:

```
preset       cells   blocked        ISOLATED (all six neighbours walkable)   stepped edges
continents   32592   7515 (23.1%)   46  (0.6% of blocked)                    9818  (1.31/cell)
highlands    32592   1319 ( 4.0%)    5  (0.4%)                               1576  (1.19/cell)
islands      32592  22205 (68.1%)   11  (0.0%)                               8294  (0.37/cell)
plains       32592    185 ( 0.6%)    0  (0.0%)                                218  (1.18/cell)
```

**99.4% of blocked cells on the shipped preset belong to a connected structure.**
So what reads as a detached shard is a real ridge seen nearly end-on from the
overhead play camera, where only a sliver of its face is presented. Whether that
*reads acceptably at play pitch* is the owner's judgement and is worth a
deliberate look — but it is not detached geometry, and nobody should go hunting
for a mesh bug.

Two other things in that table are worth the owner's attention:

- **`highlands` is 4.0% blocked.** `docs/status/terrain.md` records it as
  **44.1% dead space** before `D-20260826-passable-means-flat-enough-to-cross`.
  The fix landed and this is what it bought — the preset is genuinely open
  country now. Its cliff count falls with it (1576 stepped edges against
  continents' 9818), so **`highlands` is no longer the preset to pick when
  hunting cliffs**, which the ticket's agent-setup note recommends. Use
  `continents` (the default) or `islands`.
- **`plains` has 185 blocked cells in 32,592.** Effectively no walls at all.

## Criterion 4 — no seams; the army half is unanswered

No texture seam in any of the seven frames. "No floating or buried armies
(sampler matches mesh)" is not answerable from these instruments: the previews
place their own squads, and `forest_preview.gd` in particular samples
`TerrainChunk.height_at` **without** the client's passability clamp
(`D-20260818-a-soldier-stands-where-his-squad-could-walk`).

In `forest-godot-squad.png` the dwarves read as sitting slightly above the grass
in front of them. That is as likely the ground sloping away under a close camera,
or the missing clamp, as it is a real sampler/mesh mismatch. **Not filed** —
deciding it needs a real match on sloped ground, which is exactly what this
criterion is for.

## Criterion 5 — forests and cover. Passes.

`forest-godot.png`: dense hearts, treelines that fray rather than end in a line,
species varying by biome (conifers inland, palms on the sand), canopies visibly
interlocking — D-108's stands doing their job. `forest-godot-squad.png`: the
per-trunk clearance from the 2026-08-27 fix is visibly working; the squad stands
in a real pocket rather than inside a pine.

`cover-godot.png`: flowers, tufts, logs and boulders at sensible sizes, colours
sitting well against the ground, and **no prop hides a soldier** — the dwarves
are clear above everything. D-100's own standing requirement, and criterion 6 of
the ticket's step list.

Stone at the mountain foot (criterion 5's tail) is reachable by count — 137 stone
and 48 gold nodes on the map — but was not walked to. That needs a match.

## Bugs filed

None. The two candidates both dissolved under measurement or belong to another
ticket:

- the "detached shards" are foreshortened ridges (0.6% isolated), corrected above;
- `gen-model-preview`'s clipped building row is
  [#228](https://github.com/desktopmachineshop/my-edotmw/issues/228), filed under
  #47.

## What remains for the owner

1. **Criterion 2's judgement call** — is the sawtoothed cliff line along a
   coastline acceptable? `docs/playtest/p40-terrain-cliffs.png` is the frame. If not, the
   lever is in the mesher, not in the passability rule.
2. **Criterion 3 at play pitch** — do one-cell ridges read as walls or as shards
   from `RenderCull.PITCH_RUN` (59 degrees) rather than from this shot's shallow
   angle?
3. **Criterion 4's army half** — march a squad across sloped ground and a
   passability boundary and watch its feet.
4. **Sweep at play zoom and at low angle** over a full map (the ticket's step 1)
   — the frames here are three fixed framings, not a sweep.
5. **Lighting across camera angles** (the ticket's step 7) — every frame here is
   one sun position.
6. **Use `continents` or `islands`, not `highlands`**, if the goal is to find
   cliffs. The ticket's setup note predates the passability change.
