# Bot playtest findings

One file per playtest ticket. Each records **what a bot-vs-bot run plus automated
observation could honestly cover**, what it observed with numbers and artifact
paths, what was filed, and exactly what is left that needs the owner's hands or
eyes.

These are not a substitute for the playtests. They are the half a machine can do,
written down so the human half is shorter and better aimed.

| ticket | subject | outcome |
|---|---|---|
| [32](32-bot-findings.md) | torus seamlessness | 4 of 5 criteria discharged; motion half open |
| [41](41-bot-findings.md) | walls, gates, wall-top tier | 3 criteria green by test; placement UX is human-only |
| [44](44-bot-findings.md) | civ differentiation (Legion vs Northmen) | **CLOSED obsolete** — replaced by #207 |
| [46](46-bot-findings.md) | HUD readability and resize | layout swept at 12 sizes, passes; live readouts open |
| [47](47-bot-findings.md) | unit and building visuals, LOD | units pass; buildings blocked by #228; criterion 5 obsolete |
| [48](48-bot-findings.md) | terrain and environment visuals | 3 of 5 pass on the frames; one judgement call |
| [49](49-bot-findings.md) | performance feel | bench numbers taken (#229); feel half open |
| [50](50-bot-findings.md) | two-human LAN | wire discharged, 0 desyncs; two humans still needed |

## Instruments this pass added

- **`just gen-seam-shot SEAM HEIGHT`** (`playtest_seam_shot.gd/.tscn`) — renders
  the torus seam with armies standing on it. `q`, `r` or `corner`. Nothing in the
  estate could frame a seam: `test-client` points at a spawn, `gen-terrain-shot`
  finds a cliff, `gen-forest-preview` finds the densest wood.
- **`playtest_observe.gd`** — headless, asserts nothing, prints. Topics: `hud`
  (layout across 12 window sizes), `seam` (torus distances, flow-field routes,
  minimap wrap), `lod` (tiers and footprint), `civs` (the six-civ table),
  `terrain` (how isolated the impassable set is, per shipped preset).

  ```
  tools/godot.exe --headless --path . --script playtest_observe.gd -- --topic=hud
  ```

- **`just test-client … RESOLUTION`** — the recipe was pinned to 1280x720, which
  is the reference window `hud_layout.gd` is designed against and therefore the
  one size at which a scaling or anchoring defect is a deliberate no-op. Default
  unchanged, so every frame taken before this is still comparable.

## Where the frames are

Five are committed under `docs/playtest/` as `p40-*`, following the convention:
`p40-seam-q.png`, `p40-seam-r.png`, `p40-seam-corner.png`,
`p40-terrain-cliffs.png`, `p40-models-buildings-clipped.png`.

The rest (`cover-godot.png`, `forest-godot.png`, `forest-godot-squad.png`,
`terrain-preview.png`) are the shipped recipes' own outputs and land in the
gitignored `artifacts/` when you run them:

```
just gen-cover-preview      just gen-forest-preview
just gen-terrain-preview    just gen-model-preview
just gen-terrain-shot       just gen-seam-shot {q,r,corner}
```

## Defects filed by this pass

| issue | subject | found while |
|---|---|---|
| [#207](https://github.com/desktopmachineshop/my-edotmw/issues/207) | replacement civ-differentiation playtest (six fantasy civs) | closing #44 |
| [#208](https://github.com/desktopmachineshop/my-edotmw/issues/208) | `gen-formation-icons` runs Godot with no host-budget slot | baseline |
| [#209](https://github.com/desktopmachineshop/my-edotmw/issues/209) | `test_multi_agent_isolation` false-positives on `attach-kit`'s `--name` | baseline |
| [#210](https://github.com/desktopmachineshop/my-edotmw/issues/210) | an ally does not open a teammate's auto-gate | #41 |
| [#214](https://github.com/desktopmachineshop/my-edotmw/issues/214) | civ/AI summaries are cp1252-corrupted, and nothing reads them | #207 |
| [#215](https://github.com/desktopmachineshop/my-edotmw/issues/215) | test-unit red on main: 10 genuine failures, all #191 roster fallout | baseline |
| [#228](https://github.com/desktopmachineshop/my-edotmw/issues/228) | `gen-model-preview` clips the building row (4th instance) | #47 |
| [#229](https://github.com/desktopmachineshop/my-edotmw/issues/229) | client render at 1000 squads is 3x D-086's last measurement | #49 |
| [#230](https://github.com/desktopmachineshop/my-edotmw/issues/230) | `military_peak` reports 0 on every scenario run | #50 |

## Two things worth reading even if you skip the rest

**#215 — the unit suite is red on `main`.** 22 failing tests of 1249; twelve are
the known native-runtime shell gap and **ten are real**, all fallout from #191:
D-067's building-rush rule fails for most of the roster, `emberdeep_ram` has an
`attack_range` shorter than one hex width, and all six per-civ gatherers carry an
identical stat block.

**A correction this pass made to its own reading of a picture**
(`docs/playtests/48-bot-findings.md`). `p40-seam-corner.png` shows what look like
detached grey shards on open ground; measured, **99.4% of blocked cells on the
shipped preset belong to a connected structure**, so they are foreshortened
ridges. Recorded because the wrong reading would have sent somebody hunting a
mesh bug — the same discipline the project applies to a green number that hides
a bad picture, pointed the other way.
