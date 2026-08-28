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
# Bot-observation passes over the playtest tickets

One file per playtest ticket, written by an agent pass that discharged
as much of each ticket as **bot-vs-bot matches plus scripted observation
of the real simulation** can honestly cover, and handed the rest back.

Each file says three things, in this order:

1. **Every checklist item classified** — bot-observable or needs-a-human.
2. **What was observed**, with numbers and the log that produced them.
3. **Exactly what is left for the owner**, and why a bot cannot do it.

The standing rule these were written under is this repo's own: *a green
run is not the same as a run that happened*. Where a result looked like a
finding and turned out to be the harness, the mistake is recorded rather
than quietly corrected — see #38's "A fixture mistake worth recording"
and #36's note on the civ handover, both of which would have produced
plausible and completely false bug reports.

## The passes

| ticket | subject | filed |
|---|---|---|
| [#43](43-bot-findings.md) | full match vs AI, pacing | #217, #224 |
| [#38](38-bot-findings.md) | field combat: counters, fairness, morale, rout | #218, #219, #220 |
| [#39](39-bot-findings.md) | siege: razing, defensive fire, health UI, upgrades | #218, #227 |
| [#37](37-bot-findings.md) | production, costs, squad cap, rally | none — all clean |
| [#36](36-bot-findings.md) | economy: gathering, hauling, depletion, storehouse | none — all clean |
| [#35](35-bot-findings.md) | formations, and the RTW gap analysis re-rated | none |
| [#42](42-bot-findings.md) | match lifecycle: victory, elimination, lobby | none |

## The harnesses

`playtest_obs/*.gd` — standalone `SceneTree` scripts, run directly:

```
tools/godot.exe --headless --path . -s res://playtest_obs/obs_combat.gd
```

| script | ticket | what it stages |
|---|---|---|
| `obs_combat.gd` | #38 | mirror fairness, counters, rout, casualty integrity, a big engagement |
| `obs_counters.gd` | #38 | D-072 power table + the full missile/infantry matrix, squad-for-squad and per resource point |
| `obs_morale.gd` | #38/#39 | morale traces under building fire, against a melee control |
| `obs_siege.gd` | #39 | defensive fire, `health_fraction` on the wire, second-squad reach, upgrades, elimination |
| `obs_siege_diag.gd` | #39 | the screening-squad finding and its position control |
| `obs_production.gd` | #37 | the real `server._handle_order_produce` / `_handle_order_rally` over a `LoopbackPeer` |
| `obs_economy.gd` | #36 | node census, haul cycles, tree timing, retargeting, storehouse |
| `obs_formations.gd` | #35 | `SQUAD_INFO` wire round-trip, shape survival, RTW row survey |
| `obs_lifecycle.gd` | #42 | the elimination rule in all four states, lobby round trip |

They are **observation harnesses, not tests**: they print, they do not
assert, and they deliberately live outside `res://tests` so GUT does not
collect them. They go through the simulation's own objects — the same
`SquadSim`/`BuildingSim`/`Economy`/`Combat` wiring `server.gd` builds, and
for #37 the real server handlers — so what they measure is what a match
does, not a restatement of it.

`logs/` holds the output each one produced, copied out of the gitignored
`artifacts/` so the evidence behind every number above survives.

## The tree these were taken on

Base commit **`cc2f4c6`**, 2026-08-27. Native runtime
(`EDOTMW_RUNTIME=native`) throughout, because the docker `test` service's
1 GB `mem_limit` OOM-killed a cold import twice on a host down to ~1.2 GB
free.

**`just test-unit` is RED at this commit** — 22–24 failing of 1249,
captured in `logs/test-unit-full.log`. That is already filed by another
worker as **#215**, with #212, #211, #203, #202, #209, #208 and the older
#152 covering the same ground: all `#191` fantasy-roster fallout, plus
twelve `test_recipe_args.gd` / `test_gate_checks.gd` failures that are the
known native-runtime shell-out gap and **not defects**. Nothing about the
red suite was re-filed from these passes.

Two of those failures land directly on ticket #39 (D-067's two-squads
rule fails for 12 archetypes against a town centre and 15 against a
tower), and one lands on #35 (no unit grants `shield_wall` or `testudo`).
Both are noted in the relevant files. Every test cited *as evidence* in
these passes was checked green individually: `test_squad_turning.gd` 9/9,
`test_fearless.gd` 4/4, `test_return_to_lobby.gd` 21/21,
`test_civ_knobs.gd` 18/18, `test_economy.gd` 44/44.

## Two things to know before adding another

**A fixture that skips a handover reports a wired feature as unwired.**
`obs_economy.gd` first measured every civ's tree time as identical,
which looks exactly like the declared-and-unread family — the cause was
that it never called the equivalent of `server._hand_civs_to_sim()`.
Set `sim.civs[player]`.

**Order squads at each other, not past each other.** Ordering two sides
to points beyond one another lets them cross, separate and walk away; the
run then reports enormous attrition margins with nothing decided, which
reads as "combat does not resolve". Order each side at the other's own
start cell.
