# Playtest #47 — unit and building visuals, animation, colours, LOD: bot findings

**Ticket:** [#47](https://github.com/desktopmachineshop/my-edotmw/issues/47) — stays OPEN.
**Run:** 2026-08-27, worktree `ao/my-edotmw-85/playtest-visual-infra`, base `cc2f4c6`.
**Frames:** `artifacts/models-godot.png`, `cover-godot.png`, `forest-godot.png`,
`forest-godot-squad.png`, `seam-q.png`, `seam-r.png`, `seam-corner.png`.
All on **Intel Iris Xe**, `forward_plus`, 1400x900 (models/cover/forest at their
recipes' own sizes).

## Checklist, classified

| # | criterion | class | status |
|---|---|---|---|
| 1 | every archetype and building renders its authored model with working animation | bot-observable | **units yes**; **buildings blocked** — see #228 |
| 2 | no black/unlit/inside-out geometry, **including building interiors** | bot-observable | units clean; **interiors not shown** — see #228 |
| 3 | colours readable and consistent across 4 players | **mixed** | two colours confirmed in a frame; four needs a match |
| 4 | LOD preserves footprint at distance | bot-observable | **confirmed structurally and numerically** |
| 5 | ghost shader clearly distinct | **OBSOLETE** | there is no ghost rendering — see below |
| 6 | no lockstep animation | **human** | mechanism confirmed; the eye is the instrument |

## Criterion 5 is obsolete and should be rewritten

The ticket asks the human to *"compare a ghost (fogged) squad against a live one
side by side"* and to confirm *"ghost shader clearly distinct."* **There is no
ghost shader and no ghost rendering.** D-099 (Accepted 2026-08-16) decided:

> **A concealed squad is not drawn at all** — not in the 3D view and not on the
> minimap. Its node is explicitly hidden the frame it becomes a ghost, rather
> than left untouched.

Confirmed on disk: `shaders/` holds `building_static`, `circular_crop`,
`prop_fog`, `terrain`, `unit_anim`, `unit_corpse` and `unit_vat.gdshaderinc`.
There is no transparent/ghost variant; CLAUDE.md records it as *"deleted rather
than dormant."*

**Suggested replacement criterion**, which is what D-099 actually asks a player
to verify and is not covered anywhere else:

- [ ] A squad that leaves your vision **disappears completely** — 3D view and
      minimap both — rather than freezing in place or fading
- [ ] A **building** you have once seen **stays drawn, unfaded, forever**, even
      when nothing of yours can see it

Those two rules differ on purpose (D-030/D-101), and a player noticing the
asymmetry and reporting it as a bug is the likeliest false alarm this ticket can
produce. Worth naming in the ticket.

## What the frames show

### Units render, animate, and are not black

`gen-model-preview` draws **6 authored archetypes x 7 clips = 42 squads, 12
soldiers each**, through the real path (`UnitDef` -> `PrimitiveUnit` -> the
shipping shaders). The recipe's own anti-freeze check passed — it renders twice
and fails if the two frames are byte-identical, so the VAT is genuinely
animating rather than showing a plausible still.

```
archers        baked ["idle", "walk", "attack", "rout"]
gatherers      baked ["idle", "walk", "attack", "rout", "chop", "mine", "forage"]
militia        baked ["idle", "walk", "attack", "rout"]
spearmen       baked ["idle", "walk", "attack", "rout"]
cavalry        baked ["idle", "walk", "attack", "rout"]
heavy_infantry baked ["idle", "walk", "attack", "rout"]
```

No black or unlit soldiers anywhere in any frame — M7's two invisible-to-numbers
defects (a MultiMesh overriding `COLOR`, and every `box()` wound inside-out) are
both absent from the units.

**Note for the owner on what "every archetype" means now.** Six authored models
against a roster of **39 unit defs across six civs**. That is the designed
degradation, not a gap: `docs/status/fantasy-civs.md` records that Emberdeep
wears the dwarf models, Gildedreach borrows `heavy_infantry` and `cavalry`, and
everything else — including five civs' gatherers — is the primitive capsule tier
by the owner's explicit call. Judge whether that is *tolerable*, not whether it
is finished.

Also worth knowing: `militia` is still an authored model and `militia` is no
longer an archetype — #191 renamed it `levy`. The art is keyed by archetype
(D-046 criterion 3), so this is a name that outlived its unit.

### Buildings — blocked, and filed as [#228](https://github.com/desktopmachineshop/my-edotmw/issues/228)

`gen-model-preview` places **nine buildings** and then frames a **6x7 squad
grid**. The building row is not in the framing calculation, so it runs off the
right edge and the largest building is clipped.

That is criteria 1 and 2 for buildings, unanswerable from the instrument the
ticket names for them — and criterion 2's real content is *"look INTO large
buildings — the winding defect only shows on big objects"*, which is precisely
the building that is cut off.

**Fourth instance of that failure in that file**, and the third time it was
written down as fixed; the docstring above `_frame_grid` claims the file *"stops
being able to make the mistake its own docstring is about"*, and it does not.
Full write-up in the issue.

What *can* be said from the six buildings that are in frame: correct-looking
models (crenellated stone tower, timber wall, slatted gate, red-roofed hall,
access tower), no obvious inside-out geometry, materials reading as intended.
Nothing about interiors.

### Criterion 4 — LOD preserves footprint. Confirmed.

The tiers, read out of `client.gd`:

```
past   55.0 world units  -> at most 1073741824 soldiers drawn (i.e. all)
past  110.0 world units  -> at most 12
past      inf            -> at most 5
```

The claim "thinner, never smaller" holds **structurally**, and this was checked
at the call site rather than inferred. `client.gd:1150` sizes the squad with

```gdscript
Formation.footprint(shape, _state.alive_of(squad_id), spacing, files)["radius"]
```

— the squad's **real** strength — and that radius is what culling, the selection
click target and the separation rule all read. LOD only caps
`visible_instance_count` on the MultiMesh. Nothing in the tier path touches
`alive`.

Measured on `emberdeep_archers` (line, spacing 1.00), for scale:

```
36 men -> radius 6.09, lever 5.85
12 men -> radius 2.30, lever 2.50
 5 men -> radius 1.62, lever 2.00
```

Those shrink because a squad of 12 **is** smaller than a squad of 36 — but a
36-strong squad drawn with 12 men keeps the 6.09 radius. That is the distinction
the criterion is about, and it holds.

### Criterion 3 — colours

`models-godot.png` shows two player colours (red and blue) side by side on the
same archetype, clearly distinguishable. `PlayerColours` is tested for
distinctness elsewhere and `ClientState.colour_of` is the single source
(D-052) read by the 3D view, the minimap (#82's fix) and the scoreboard (D-102).

Four players in one melee is still the owner's check — distinctness in a lit
preview and distinctness in a mêlée at play zoom are different questions, and the
second is the one the criterion asks.

### Criterion 6 — lockstep

The mechanism is right by construction: `phase = fract(t * rate + hash(slot))`
computed in the shader from `TIME` (D-082), with `AnimationState.man_rate`
spreading per-man rates so a crew that starts together separates. There is
nowhere for a per-soldier phase accumulator to live, which is the point.

A still cannot show unison. This one is the owner's eye, and the place to look
is a **gathering crew**, where `docs/status/gatherer-tools.md` records the
cadence (`AnimationState.CHOP_RATE` and siblings) as explicitly untested and
owner-judged.

### Trees and props (D-087, D-100) look right

`forest-godot.png` and `forest-godot-squad.png`: dense forest hearts, fraying
treelines, species varying by biome (conifers inland, palms on the sand),
canopies interlocking, fruit on the orchard trees. `cover-godot.png`: flowers,
tufts, logs and boulders at sensible sizes and colours against the ground.

**No prop hides a soldier** in either frame, which is D-100's own standing
requirement and #48's criterion 6.

One thing worth the owner's eye rather than a bug report: in
`forest-godot-squad.png` the dwarves read as sitting slightly **above** the grass
in front of them. It may be the ground sloping away under a close camera, and it
may be that `forest_preview.gd` samples height without applying the client's
passability clamp (`D-20260818-a-soldier-stands-where-his-squad-could-walk`) —
which it does not. Not filed, because the instrument is the likelier cause and
"floating or buried armies" is on **#48**'s checklist where a real match will
answer it.

## Bugs filed

- [#228](https://github.com/desktopmachineshop/my-edotmw/issues/228) —
  `gen-model-preview` clips the building row.

## What remains for the owner

1. **Criteria 1 and 2 for buildings** — blocked on #228, or done by eye in a live
   match. Construction state (the progress scale) and building interiors are both
   unshown by any current instrument.
2. **Criterion 3 with four players in a melee.**
3. **Criterion 6 — lockstep** — watch a gathering crew and a marching line.
4. **Criterion 5, rewritten** — a squad leaving vision should vanish entirely; a
   building once seen should stay drawn unfaded. Please update the ticket text;
   the ghost shader it names has been deleted since D-099.
5. The floating-boots question above, in a real match on sloped ground.
