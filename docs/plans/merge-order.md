# Merge order for the open PR queue

**Generated 2026-08-28**, from GitHub's own `baseRefName` edges and per-PR
changed-file lists for the 74 PRs open at that moment. Every table is
mechanical; regenerate rather than trust it once PRs start landing.

**Method.** Chains are built from each PR's actual base branch. A PR based on
`main` is a chain ROOT. "Conflict" means two PRs on *independent* chains change
the same file, so whichever merges second must rebase. New decision entries and
playtest images are excluded from the conflict counts because they are new
files — except where two chains create the same decision *filename*, which is
a content collision and is called out separately.

- 74 open PRs, 31 chain roots, all reported MERGEABLE by GitHub.
- Largest chains: **#205 (14 PRs, 144 files)**, **#250 (12 PRs, 112 files)**,
  #222 (7), #216 (7), #225 (4). Longest path is **12 deep**:
  `#205 → #213 → #239 → #242 → #256 → #258 → #264 →
  #295 → #300 → #306 → #320 → #348`. #340 is also 12 deep, on
  the #250 chain.
- No CI is configured on this repository, so "green" means a local
  `just test-unit`, not a check on the PR.

## 1. Read this first — three things no merge ORDER can fix

### 1.1 PR #340 is not stage 8. It is the whole naval stack on the wrong root.

> **CORRECTED BY THE REHEARSAL (see the log at the end of this file).** This
> section is wrong. Naval stages 1, 3 and 4 are *genuine ancestors* of #340,
> so it builds on the naval chain rather than duplicating it, and merged in
> the order below it costs **two trivial conflicts**. The "41 of 62 files"
> figure below is an artefact of `gh pr view --json files` reporting the diff
> against #340's *base* (the perf-chain tip). The real rival implementation is
> **#308 against #343**, which could not be merged at all. Left in place
> rather than deleted so the correction is visible.

`#340 ao/my-edotmw-87/naval-8-presentation` is based on the **my-edotmw-87
performance chain** (root #250), not on the naval chain. Its diff carries **41
of the naval chain's 62 files** — the water graph, the movement domain, docks,
embark and the whole hull roster — as well as its own presentation work. Its
copy of `decisions/D-20260828-water-is-a-second-movement-domain.md` is
**byte-identical** to #343's (md5 `22bb849a`), which is what confirms it is a
rebase of that work rather than an addition on top of it.

Merging both the naval chain and #340 double-applies naval. **Somebody has to
decide which branch carries naval before either is merged**, and no ordering
avoids it. This is the largest single item in the queue.

### 1.2 The hulls and the dock are shipped by three independent chains

`buildings/dock.tres`, `units/*_warship.tres`, `units/*_transport.tres`,
`units/*_warboat.tres`, `tests/test_naval_roster.gd` and the naval fields in
`unit_def.gd` are each created by **#314** (its own root, on `main`), **#323**
(root #216) and **#340** (root #250). #314 overlaps the naval chain on 17 files
and #340 on 17. Two of the three have to be dropped or reduced to a delta.

### 1.3 One decision id, two different documents

> **RULED 2026-08-28 (orchestrator): #343 wins, #308 merges design-only.**
> The full resolution, including two colliding files the ruling did not name,
> is in the Rulings section of the rehearsal log at the end of this file.

`decisions/D-20260828-water-is-a-second-movement-domain.md` exists on three
branches: #343 and #340 are identical at 9,039 bytes, and **#308's is a
different document at 9,436 bytes**. The project's rule is one file per decision
and never a renumber, so this needs the authors to reconcile it, not a merge
resolution. `D-20260828-the-water-graph-is-the-inverse-of-the-ground.md` is
likewise in both #313 and #340.

## 2. Recommended first six merges

| # | PR | branch | why this one first |
|---|---|---|---|
| 1 | #222 | `ao/my-edotmw-82/d067-siege-rule` | the D-067 re-derivation the whole balance cluster sits behind, and #243/#252 are stacked on it |
| 2 | #324 | `ao/my-edotmw-82/formations-granted` | must land BEFORE #243 (#360): it supplies the formation grants, so #243 never passes through a state where the guard fails |
| 3 | #243 | `ao/my-edotmw-86/red-main` | makes `test-unit` green and the docker estate runnable; four PRs are stacked on it and nothing else can be tested honestly until it lands |
| 4 | #265 | `ao/my-edotmw-80/gap-assessment` | one file, docs only — zero conflict surface |
| 5 | #238 | `ao/my-edotmw-81/issue-153-gate-reconciles-containers` | `justfile` only, no shipped code |
| 6 | #226 | `ao/my-edotmw-81/issue-157-second-match-state` | six files, `server.gd` only, self-contained |

#222 then #243 is both the orchestrator's directive and what the graph
requires; **#324 goes between them** by the #360 resolution, which is free
and removes a conflict rather than deferring one.

## 3. Merge order

Within a chain the order is forced — parent before child. Between chains, the
order below puts the chain that OWNS a contended file ahead of the chains that
merely touch it, so the later ones rebase onto a settled version.

### Wave 1 — make main green

Blocking, and strictly in this order: #243 is stacked on #222, and #273/#294/#335/#345 are all stacked on #243. Nothing else in the queue can be tested honestly until #243 lands. **#324 is moved here from Wave 3 and merges BEFORE
#243** (#360). It supplies the formation grants first, so #243 — which
drops its own four on its branch — never passes through a state where the
formations guard fails. Free, and it removes the conflict entirely.

| order | PR | base | branch | what it is |
|---|---|---|---|---|
| 1 | #222 | main | `ao/my-edotmw-82/d067-siege-rule` | Re-derive D-067's numbers, and ask the pair rule of LINE troops (#152) |
| 2 | #324 | main | `ao/my-edotmw-82/formations-granted` | Two formations that belonged to nobody (#309) |
| 3 | #243 | #222 | `ao/my-edotmw-86/red-main` | Make test-unit green and the docker estate runnable again (#223, #215, #208, #209) |
| 4 | #335 | #243 | `ao/my-edotmw-86/small-fixes` | Small-fix batch: #302 #249 #253 #254 #276 |
| 5 | #294 | #243 | `ao/my-edotmw-86/ci-pipeline` | CI: run the checks the machine can run (#290) |
| 6 | #273 | #243 | `ao/my-edotmw-86/explore-command` | Explore: a squad that hunts fog on its own until told to stop (#120) |
| 7 | #345 | #243 | `ao/my-edotmw-86/audio-foundations` | Audio foundations: a sound is a cosmetic, and you must be able to SEE its cause (#344) |

### Wave 2 — low-conflict singles

Independent chains of one, each touching at most one hot file. Merge in any order; they exist to bank reviews and shrink the queue.

| order | PR | base | branch | what it is |
|---|---|---|---|---|
| 1 | #265 | main | `ao/my-edotmw-80/gap-assessment` | docs: senior-gamedev gap assessment — content, onboarding, perf, product, process |
| 2 | #238 | main | `ao/my-edotmw-81/issue-153-gate-reconciles-containers` | fix(gate): charge the work, not the launcher (#153) |
| 3 | #226 | main | `ao/my-edotmw-81/issue-157-second-match-state` | fix(server): a client record forgets the match it left (#157) |
| 4 | #232 | main | `ao/my-edotmw-81/issue-162-disconnect-notice` | feat(client): a client with no server says so (#162) |
| 5 | #235 | main | `ao/my-edotmw-87/model-preview-framing` | fix(preview): gen-model-preview frames what it DREW, not one grid of it (#228) |
| 6 | #237 | main | `ao/my-edotmw-87/artifacts-are-writable` | fix(artifacts): write where the build can write, and say where that is (#201) |
| 7 | #234 | main | `ao/my-edotmw-85/playtest-visual-infra` | Bot playtest pass: visual/infra tickets #32 #41 #44 #46 #47 #48 #49 #50 |
| 8 | #251 | main | `ao/my-edotmw-82/ladder-instrument` | The ladder asserts the match ENDED, and a decided one stops (#224) |
| 9 | #248 | main | `ao/my-edotmw-82/clash-reports-its-army` | A scenario's gates are what that scenario contains (#230) |
| 10 | #255 | main | `ao/my-edotmw-80/ai-founding-and-gates` | fix(ai/walls): a refused founding retries elsewhere; auto gates open for allies |
| 11 | #322 | main | `ao/my-edotmw-81/issue-292-disconnect-eliminates` | fix(match): leaving a match leaves nothing behind (#292, #318) |

Cross-chain file collisions *inside* this wave, so the second of each
pair rebases:

- #238 and #234 — `justfile`
- #238 and #251 — `justfile`
- #238 and #248 — `justfile`
- #226 and #237 — `server.gd`
- #226 and #251 — `server.gd`
- #226 and #248 — `server.gd`
- #226 and #255 — `server.gd`
- #226 and #322 — `server.gd`
- #232 and #237 — `client.gd`
- #232 and #255 — `docs/status/playtests-2026-08.md`
- #232 and #322 — `docs/status/playtests-2026-08.md`
- #235 and #237 — `model_preview.gd`
- #237 and #251 — `server.gd`
- #237 and #248 — `server.gd`
- #237 and #255 — `server.gd`
- #237 and #322 — `server.gd`
- #234 and #251 — `justfile`
- #234 and #248 — `justfile`
- #251 and #248 — `justfile`, `server.gd`
- #251 and #255 — `docs/status/ai-opponent.md`, `server.gd`
- #251 and #322 — `server.gd`
- #248 and #255 — `server.gd`
- #248 and #322 — `server.gd`
- #255 and #322 — `docs/status/playtests-2026-08.md`, `server.gd`

### Wave 3 — the balance / civ cluster (my-edotmw-82)

Mostly roster `.tres` and tests. #334 must precede #347 (stacked) and #222 must already be in (#252 is stacked on it).

| order | PR | base | branch | what it is |
|---|---|---|---|---|
| 1 | #221 | main | `ao/my-edotmw-82/lod-hysteresis` | A LOD tier is sticky, and the distance it reads is a minimum (#155) |
| 2 | #252 | #222 | `ao/my-edotmw-82/d067-garrison` | D-067 is a rush rule, and a rush has no garrison (#227) |
| 3 | #260 | main | `ao/my-edotmw-82/d072-screen` | D-072's screen is runnable, and every violation is in its blind spot (#220) |
| 4 | #261 | main | `ao/my-edotmw-82/counters-are-felt` | The counter triangle is measured, and one armour class is doing all the work (#219) |
| 5 | #321 | main | `ao/my-edotmw-82/civ-can-open` | A civ must be able to afford its own opening (#247, #275) |
| 6 | #330 | main | `ao/my-edotmw-82/gatherers-differ` | The crew is a civ's unit too (#269) |
| 7 | #334 | main | `ao/my-edotmw-82/armour-is-role` | Armour class is a role, not a flavour (#268) |
| 8 | #347 | #334 | `ao/my-edotmw-82/levies-are-sidegrades` | fix(roster): a levy is a sidegrade, and a duel is not the test (#267) |
| 9 | #328 | main | `ao/my-edotmw-82/morale-scales` | Morale is a fraction of the squad, not a count of men (#266) |
| 10 | #257 | main | `ao/my-edotmw-82/fortifications-frighten` | A fortification frightens men: no morale recovery under fire (#218) |
| 11 | #297 | main | `ao/my-edotmw-82/surrender` | A player may concede (#279) |
| 12 | #336 | main | `ao/my-edotmw-82/civ-knobs` | Four more knobs, and every one has a caller (#270) |

Cross-chain file collisions *inside* this wave, so the second of each
pair rebases:

- #221 and #297 — `client.gd`
- #324 and #347 — `units/emberdeep_levy.tres`
- #328 and #257 — `combat.gd`
- #257 and #336 — `squad_sim.gd`
- #297 and #336 — `building_sim.gd`, `server.gd`

### Wave 4 — playtest and assessment docs

Documentation-heavy, so merge late enough to describe the merged tree and early enough not to rot. #299 also carries `squad_sim.gd` and `unit_def.gd`.

| order | PR | base | branch | what it is |
|---|---|---|---|---|
| 1 | #233 | main | `ao/my-edotmw-84/playtest-bot-findings` | docs(playtest): bot-observation passes over seven playtest tickets (#43 #38 #39 #37 #36 #35 #42) |
| 2 | #293 | #233 | `ao/my-edotmw-88/playtest-207` | Bot playtest pass: civ differentiation across the six fantasy civs (#207) |
| 3 | #299 | main | `ao/my-edotmw-80/three-decisions` | Three decisions: retire islands, revisit host-quit, and guard the imported docs (#280 #289 #291) |

### Wave 5 — the my-edotmw-83 tech/pacing chain

Touches `server.gd`, `client.gd`, `squad_sim.gd`, every `civs/*.tres` and the `justfile`. Merge as a block, after the balance cluster has settled the rosters.

| order | PR | base | branch | what it is |
|---|---|---|---|---|
| 1 | #225 | main | `ao/my-edotmw-83/tech-tree` | The civ tech tree: buildings research techs, and completing the defining line IS the age-up (#206) |
| 2 | #296 | #225 | `ao/my-edotmw-83/ladder-and-pacing` | One decision entry for the epoch ladder (#278), and a measured rate under D-068 (#281) |
| 3 | #319 | #225 | `ao/my-edotmw-83/tick-ladder` | The M6 rise has a name (#304), and separation stops over-scanning |
| 4 | #341 | #319 | `ao/my-edotmw-83/shipping-scale` | D-018's successor number, measured: ~200 squads — and the tick at that scale with water (#287, #105) |

### Wave 6 — the my-edotmw-87 performance chain

Strictly linear and heavy on `client.gd`. **#340 is deliberately excluded** — see section 1.1. Merge up to #331 and stop. #310 re-encodes every `civs/*.tres`, so it must come after anything else that edits them.

| order | PR | base | branch | what it is |
|---|---|---|---|---|
| 1 | #250 | main | `ao/my-edotmw-87/render-cost-attribution` | perf(client): every microsecond of a frame has a phase — #229 attributed, and the loop hoisted |
| 2 | #263 | #250 | `ao/my-edotmw-87/bench-is-the-client` | perf(bench): the benchmark runs the client's own render pipeline (#240) |
| 3 | #272 | #263 | `ao/my-edotmw-87/one-cell-per-drawn-man` | perf(derive): one cell derivation per drawn man, not two (#245) |
| 4 | #274 | #272 | `ao/my-edotmw-87/the-clamp-after-one-cell` | docs(clamp): #244 answered NO — the measurement moved under it |
| 5 | #298 | #274 | `ao/my-edotmw-87/render-cost-has-a-baseline` | feat(bench): render cost has a recorded baseline and a loud delta (#286) |
| 6 | #307 | #298 | `ao/my-edotmw-87/the-jostle-looks-where-the-men-are` | perf(client): the jostle looks where the men are (#262) |
| 7 | #310 | #307 | `ao/my-edotmw-87/every-tres-is-utf8` | fix(data): every shipped text file decodes as UTF-8 (#236) |
| 8 | #317 | #310 | `ao/my-edotmw-87/inside-the-derive-phase` | perf(derive): attribute the phase, take the two hoists, file the rest |
| 9 | #326 | #317 | `ao/my-edotmw-87/inside-the-decoration-phase` | perf(client): a squad looks up its buildings, it does not walk the match (#325) |
| 10 | #329 | #326 | `ao/my-edotmw-87/the-gather-stops-repeating` | perf(client): one call for a disk of cells, and a memo that did not pay |
| 11 | #331 | #329 | `ao/my-edotmw-87/inside-the-pipeline` | docs(perf): attribute inside the pipeline, so the remaining levers are measured |

### Wave 7 — the my-edotmw-79 M8/Steam chain

The largest chain in the queue at 14 PRs and 144 files, heavy on `server.gd`, `client.gd` and the `justfile`. #271 branches off #205 and #303 off #258, so both can land earlier than the tail.

| order | PR | base | branch | what it is |
|---|---|---|---|---|
| 1 | #205 | main | `ao/my-edotmw-79/export` | feat(build): just export produces the shipping builds from one version (#178) |
| 2 | #213 | #205 | `ao/my-edotmw-79/handshake` | feat(net): the join flow carries a protocol version, and a stale build is refused (#179) |
| 3 | #239 | #213 | `ao/my-edotmw-79/main-menu` | feat(client): a client starts before it connects, and lands back on a menu (#180) |
| 4 | #242 | #239 | `ao/my-edotmw-79/steam-boundary` | feat(steam): one script names Steam, and a test makes that structural (#181) |
| 5 | #256 | #242 | `ao/my-edotmw-79/host-in-process` | feat(host): the host runs the server inside its own client (#182) |
| 6 | #258 | #256 | `ao/my-edotmw-79/alpha-loop` | feat(alpha): a versioned zip, a runbook, and the page a tester reads (#183) |
| 7 | #264 | #258 | `ao/my-edotmw-79/steam-transport` | feat(net): a transport is a seam, and ordering is a contract that can fail (#184) |
| 8 | #295 | #264 | `ao/my-edotmw-79/onboarding` | feat(lobby): a civ says what it is before you pick it (#283) |
| 9 | #300 | #295 | `ao/my-edotmw-79/opening-hint` | feat(hud): the opening says which squad founds, from the rule the server enforces (#284) |
| 10 | #306 | #300 | `ao/my-edotmw-79/controls-screen` | feat(ui): the controls are written down once, and say what the code does (#282) |
| 11 | #320 | #306 | `ao/my-edotmw-79/manual` | feat(manual): the manual is generated, or it is stamped (#305) |
| 12 | #348 | #320 | `ao/my-edotmw-79/ai-fortifies` | feat(ai): an AI that fortifies, and the question naval shares with it (#337) |
| 13 | #271 | #205 | `ao/my-edotmw-81/issue-185-steam-depot` | feat(steam): a depot upload is validated before it is authenticated (#185) |
| 14 | #303 | #258 | `ao/my-edotmw-81/issue-288-report-a-problem` | feat(alpha): a tester can send back what happened, in one file (#288) |

### Wave 8 — economy

#312 is stacked on #246. Both touch `building_sim.gd` and `server.gd`.

| order | PR | base | branch | what it is |
|---|---|---|---|---|
| 1 | #246 | main | `ao/my-edotmw-88/renewable-food` | Food is GROWN, not only found: the farm (#159), plus two .tres cleanups (#231, #214) |
| 2 | #312 | #246 | `ao/my-edotmw-82/renewable-metals` | A vein runs deep: it does not run out (#277) |

### Wave 9 — naval, ONLY after section 1 is resolved

Do not start this wave until somebody has decided whether naval ships via the #216 chain or via #340, and which of #314/#323/#340 owns the hulls. The order shown is the branch graph's, which runs stages 1, 3, 4, 2, 7 — not stage order.

| order | PR | base | branch | what it is |
|---|---|---|---|---|
| 1 | #216 | main | `ao/my-edotmw-80/map-spawn-fixes` | fix(map/hud): every start shares one landmass; minimap clicks read the crop |
| 2 | #313 | #216 | `ao/my-edotmw-81/naval-1-water-graph` | feat(naval): the water graph — navigability, shores, and water components (#301) |
| 3 | #323 | #313 | `ao/my-edotmw-88/naval-3-docks` | Naval stage 3: docks — a shore rule, a water side, and hulls in the sea (#301) |
| 4 | #333 | #323 | `ao/my-edotmw-88/naval-4-embark` | Naval stage 4: embark, disembark, and what a carried squad is (#301) |
| 5 | #343 | #333 | `ao/my-edotmw-88/naval-2-domain` | Naval stage 2: water is a second movement domain, with a measured budget (#301) |
| 6 | #342 | #343 | `ao/my-edotmw-81/naval-7-ai-and-bots` | feat(naval): the AI sails, and a landing happens in a played match (#301, stage 7) |
| 7 | #327 | #313 | `ao/my-edotmw-81/naval-5-shoreline-combat` | feat(naval): melee does not cross a shoreline (#301, stage 5) |
| 8 | #314 | main | `ao/my-edotmw-88/naval-6-content` | Naval stage 6: the ten hulls, the dock, and the D-072 screen as tests (#301) |
| 9 | #308 | #299 | `ao/my-edotmw-80/naval-design` | Naval: the design, the pinned interface contract, AND stage 2 (water domain) — #301 |
| 10 | #340 | #331 | `ao/my-edotmw-87/naval-8-presentation` | Naval stage 8: a rendered frame of ships on water (#301) |

Cross-chain file collisions *inside* this wave, so the second of each
pair rebases:

- #216 and #308 — `CLAUDE.md`
- #216 and #340 — `CLAUDE.md`, `client.gd`, `docs/status/playtests-2026-08.md`, `docs/status/spawns.md`, `map_config.gd`, `minimap_paint.gd`, `terrain_gen.gd`, `tests/test_map_symmetry.gd`, `tests/test_minimap_paint.gd`, `tests/test_production_spawn.gd`, `tests/test_production_spawn.gd.uid`
- #313 and #308 — `CLAUDE.md`
- #313 and #340 — `CLAUDE.md`, `build/steam/app_build_480.vdf`, `build/steam/depot_build_481.vdf`, `docs/status/naval.md`, `terrain_gen.gd`, `tests/test_water_graph.gd`, `tests/test_water_graph.gd.uid`
- #323 and #314 — `bot_build_plan.gd`, `buildings/dock.tres`, `tests/test_bot_build_plan.gd`, `tests/test_naval_roster.gd`, `tests/test_naval_roster.gd.uid`, `unit_def.gd`, `units/emberdeep_transport.tres`, `units/emberdeep_warship.tres`, `units/gildedreach_transport.tres`, `units/gildedreach_warship.tres`, `units/gravesworn_transport.tres`, `units/gravesworn_warship.tres`, `units/stoneblood_warboat.tres`, `units/thornwood_transport.tres`, `units/thornwood_warship.tres`, `units/windmarch_warboat.tres`
- #323 and #308 — `squad_sim.gd`, `unit_def.gd`
- #323 and #340 — `bot_build_plan.gd`, `building_def.gd`, `building_sim.gd`, `buildings/dock.tres`, `server.gd`, `squad_sim.gd`, `tests/test_bot_build_plan.gd`, `tests/test_naval_docks.gd`, `tests/test_naval_docks.gd.uid`, `tests/test_naval_roster.gd`, `tests/test_naval_roster.gd.uid`, `unit_def.gd`, `units/emberdeep_transport.tres`, `units/emberdeep_warship.tres`, `units/gildedreach_transport.tres`, `units/gildedreach_warship.tres`, `units/gravesworn_transport.tres`, `units/gravesworn_warship.tres`, `units/stoneblood_warboat.tres`, `units/thornwood_transport.tres`, `units/thornwood_warship.tres`, `units/windmarch_warboat.tres`
- #333 and #308 — `squad_sim.gd`
- #333 and #340 — `client_state.gd`, `match_state.gd`, `net_protocol.gd`, `server.gd`, `squad_sim.gd`, `tests/test_naval_embark.gd`, `tests/test_naval_embark.gd.uid`
- #343 and #308 — `squad_sim.gd`
- #343 and #340 — `playtest_obs/obs_water_budget.gd`, `playtest_obs/obs_water_budget.gd.uid`, `squad_sim.gd`, `tests/test_naval_domain.gd`, `tests/test_naval_domain.gd.uid`, `tests/test_naval_embark.gd`
- #342 and #308 — `squad_sim.gd`
- #342 and #340 — `docs/status/naval.md`, `squad_sim.gd`
- #327 and #308 — `squad_sim.gd`
- #327 and #340 — `docs/status/naval.md`, `squad_sim.gd`
- #314 and #308 — `unit_def.gd`
- #314 and #340 — `bot_build_plan.gd`, `buildings/dock.tres`, `tests/test_bot_build_plan.gd`, `tests/test_naval_roster.gd`, `tests/test_naval_roster.gd.uid`, `unit_def.gd`, `units/emberdeep_transport.tres`, `units/emberdeep_warship.tres`, `units/gildedreach_transport.tres`, `units/gildedreach_warship.tres`, `units/gravesworn_transport.tres`, `units/gravesworn_warship.tres`, `units/stoneblood_warboat.tres`, `units/thornwood_transport.tres`, `units/thornwood_warship.tres`, `units/windmarch_warboat.tres`
- #308 and #340 — `CLAUDE.md`, `squad_sim.gd`, `unit_def.gd`

## 4. Expected conflicts between independent chains

Only files changed by PRs on **different** chains — inside a chain the parent
merges first, so those are not conflicts. Sorted by how many independent chains
touch the file, which is the number that predicts pain.

| file | chains | PRs that change it (chain root in brackets) |
|---|---|---|
| `server.gd` | 14 | #205[205], #213[205], #225[225], #226[226], #237[237], #246[246], #248[248], #251[251], #255[255], #256[205], #264[205], #273[222], #297[297], #303… |
| `client.gd` | 10 | #205[205], #213[205], #216[216], #221[221], #225[225], #232[232], #237[237], #239[205], #246[246], #256[205], #263[250], #264[205], #272[250], #273… |
| `CLAUDE.md` | 8 | #205[205], #213[205], #216[216], #225[225], #237[237], #239[205], #242[205], #246[246], #250[250], #256[205], #258[205], #263[250], #264[205], #271… |
| `justfile` | 8 | #205[205], #213[205], #234[234], #238[238], #239[205], #242[205], #243[222], #248[248], #250[250], #251[251], #256[205], #258[205], #264[205], #271… |
| `building_sim.gd` | 7 | #225[225], #246[246], #297[297], #322[322], #323[216], #336[336], #340[250] |
| `squad_sim.gd` | 7 | #225[225], #257[257], #273[222], #308[299], #319[225], #323[216], #327[216], #333[216], #335[222], #336[336], #340[250], #342[216], #343[216] |
| `bot_build_plan.gd` | 6 | #225[225], #246[246], #314[314], #323[216], #340[250], #348[205] |
| `client_state.gd` | 6 | #213[205], #225[225], #239[205], #246[246], #272[250], #273[222], #333[216], #340[250], #345[222] |
| `net_protocol.gd` | 6 | #213[205], #225[225], #273[222], #297[297], #333[216], #340[250] |
| `ai_player.gd` | 5 | #225[225], #246[246], #255[255], #342[216], #348[205] |
| `civs/emberdeep.tres` | 5 | #225[225], #246[246], #295[205], #310[250], #336[336] |
| `civs/gravesworn.tres` | 5 | #225[225], #246[246], #295[205], #310[250], #321[321] |
| `civs/stoneblood.tres` | 5 | #225[225], #246[246], #295[205], #310[250], #336[336] |
| `civs/thornwood.tres` | 5 | #225[225], #246[246], #295[205], #310[250], #336[336] |
| `civs/windmarch.tres` | 5 | #225[225], #246[246], #295[205], #310[250], #336[336] |
| `docs/status/playtests-2026-08.md` | 5 | #216[216], #232[232], #255[255], #322[322], #340[250] |
| `unit_def.gd` | 5 | #308[299], #314[314], #323[216], #328[328], #340[250] |
| `ai/cautious.tres` | 4 | #246[246], #295[205], #310[250], #342[216], #348[205] |
| `ai_profile.gd` | 4 | #225[225], #246[246], #342[216], #348[205] |
| `bot_client.gd` | 4 | #205[205], #213[205], #225[225], #246[246], #248[248], #348[205] |
| `building_def.gd` | 4 | #225[225], #246[246], #323[216], #340[250] |
| `civs/gildedreach.tres` | 4 | #225[225], #246[246], #295[205], #310[250] |
| `combat.gd` | 4 | #257[257], #327[216], #328[328], #335[222], #342[216] |
| `tests/test_bot_build_plan.gd` | 4 | #246[246], #314[314], #323[216], #340[250] |
| `ai/balanced.tres` | 3 | #246[246], #342[216], #348[205] |
| `ai/relentless.tres` | 3 | #246[246], #342[216], #348[205] |
| `buildings/dock.tres` | 3 | #314[314], #323[216], #340[250] |
| `civ_def.gd` | 3 | #225[225], #295[205], #336[336] |
| `docs/status/ai-opponent.md` | 3 | #246[246], #251[251], #255[255] |
| `docs/status/spawns.md` | 3 | #216[216], #299[299], #340[250] |
| `match_state.gd` | 3 | #333[216], #335[222], #340[250] |
| `model_preview.gd` | 3 | #235[235], #237[237], #303[205] |
| `tests/test_multi_agent_isolation.gd` | 3 | #238[238], #239[205], #243[222] |
| `tests/test_naval_roster.gd` | 3 | #314[314], #323[216], #340[250] |

**How to read it.** `server.gd` (14 chains, 20 PRs) and `client.gd` (10 chains,
26 PRs) will conflict textually on nearly every merge after the first few. Both
are dispatch/`_ready` files where the changes are additive, so those conflicts
are *mechanical* — two PRs adding a case to the same match statement. Budget
for them rather than re-planning around them.

The ones that are **not** mechanical, and want a named owner:

- **`squad_sim.gd`** — 7 chains, 13 PRs (#225, #257, #273, #308, #319, #323,
  #327, #333, #335, #336, #340, #342, #343). #319 *restructures* the tick phases
  (separation over-scanning) while #257 adds a morale-suppression read and the
  naval PRs add a second movement domain. **Merge #319 before #257 and before
  naval**, or those rebase onto a tick loop that has moved under them.
- **`combat.gd`** — 4 chains (#257, #327, #328, #335, #342). #257 (no morale
  recovery under fire) and #328 (morale as a fraction of the squad, not a count
  of men) are two edits to the same morale arithmetic from different roots.
  **Merge #328 first**: it changes what a casualty COSTS, so #257's constants
  are then reviewable against the final numbers instead of the old ones.
- **`unit_def.gd`** — 5 chains (#308, #314, #323, #328, #340). #328 adds the
  morale-scaling function; the other four all add naval fields. These are schema
  additions, so `decisions/D-010.md`'s schema log conflicts alongside them.
- **every `civs/*.tres`** — 5 chains (#225, #246, #295, #310, #321, #336).
  #310 re-encodes them as UTF-8 (#236) while the others add fields or change
  numbers. **Merge #310 last of that set.** A re-encode of a file somebody else
  also edited is the one conflict git resolves badly, because every line reads
  as changed.
- **`bot_build_plan.gd` and its test** — 4 chains each, and three of them
  (#314, #323, #340) are the duplicated naval work from section 1.2 rather than
  four independent changes.

## 5. Every open PR

| PR | chain root | base | branch | what it is |
|---|---|---|---|---|
| #205 | #205 | main | `ao/my-edotmw-79/export` | feat(build): just export produces the shipping builds from one version (#178) |
| #213 | #205 | #205 | `ao/my-edotmw-79/handshake` | feat(net): the join flow carries a protocol version, and a stale build is refused (#179) |
| #216 | #216 | main | `ao/my-edotmw-80/map-spawn-fixes` | fix(map/hud): every start shares one landmass; minimap clicks read the crop |
| #221 | #221 | main | `ao/my-edotmw-82/lod-hysteresis` | A LOD tier is sticky, and the distance it reads is a minimum (#155) |
| #222 | #222 | main | `ao/my-edotmw-82/d067-siege-rule` | Re-derive D-067's numbers, and ask the pair rule of LINE troops (#152) |
| #225 | #225 | main | `ao/my-edotmw-83/tech-tree` | The civ tech tree: buildings research techs, and completing the defining line IS the age-up (#206) |
| #226 | #226 | main | `ao/my-edotmw-81/issue-157-second-match-state` | fix(server): a client record forgets the match it left (#157) |
| #232 | #232 | main | `ao/my-edotmw-81/issue-162-disconnect-notice` | feat(client): a client with no server says so (#162) |
| #233 | #233 | main | `ao/my-edotmw-84/playtest-bot-findings` | docs(playtest): bot-observation passes over seven playtest tickets (#43 #38 #39 #37 #36 #35 #42) |
| #234 | #234 | main | `ao/my-edotmw-85/playtest-visual-infra` | Bot playtest pass: visual/infra tickets #32 #41 #44 #46 #47 #48 #49 #50 |
| #235 | #235 | main | `ao/my-edotmw-87/model-preview-framing` | fix(preview): gen-model-preview frames what it DREW, not one grid of it (#228) |
| #237 | #237 | main | `ao/my-edotmw-87/artifacts-are-writable` | fix(artifacts): write where the build can write, and say where that is (#201) |
| #238 | #238 | main | `ao/my-edotmw-81/issue-153-gate-reconciles-containers` | fix(gate): charge the work, not the launcher (#153) |
| #239 | #205 | #213 | `ao/my-edotmw-79/main-menu` | feat(client): a client starts before it connects, and lands back on a menu (#180) |
| #242 | #205 | #239 | `ao/my-edotmw-79/steam-boundary` | feat(steam): one script names Steam, and a test makes that structural (#181) |
| #243 | #222 | #222 | `ao/my-edotmw-86/red-main` | Make test-unit green and the docker estate runnable again (#223, #215, #208, #209) |
| #246 | #246 | main | `ao/my-edotmw-88/renewable-food` | Food is GROWN, not only found: the farm (#159), plus two .tres cleanups (#231, #214) |
| #248 | #248 | main | `ao/my-edotmw-82/clash-reports-its-army` | A scenario's gates are what that scenario contains (#230) |
| #250 | #250 | main | `ao/my-edotmw-87/render-cost-attribution` | perf(client): every microsecond of a frame has a phase — #229 attributed, and the loop hoisted |
| #251 | #251 | main | `ao/my-edotmw-82/ladder-instrument` | The ladder asserts the match ENDED, and a decided one stops (#224) |
| #252 | #222 | #222 | `ao/my-edotmw-82/d067-garrison` | D-067 is a rush rule, and a rush has no garrison (#227) |
| #255 | #255 | main | `ao/my-edotmw-80/ai-founding-and-gates` | fix(ai/walls): a refused founding retries elsewhere; auto gates open for allies |
| #256 | #205 | #242 | `ao/my-edotmw-79/host-in-process` | feat(host): the host runs the server inside its own client (#182) |
| #257 | #257 | main | `ao/my-edotmw-82/fortifications-frighten` | A fortification frightens men: no morale recovery under fire (#218) |
| #258 | #205 | #256 | `ao/my-edotmw-79/alpha-loop` | feat(alpha): a versioned zip, a runbook, and the page a tester reads (#183) |
| #260 | #260 | main | `ao/my-edotmw-82/d072-screen` | D-072's screen is runnable, and every violation is in its blind spot (#220) |
| #261 | #261 | main | `ao/my-edotmw-82/counters-are-felt` | The counter triangle is measured, and one armour class is doing all the work (#219) |
| #263 | #250 | #250 | `ao/my-edotmw-87/bench-is-the-client` | perf(bench): the benchmark runs the client's own render pipeline (#240) |
| #264 | #205 | #258 | `ao/my-edotmw-79/steam-transport` | feat(net): a transport is a seam, and ordering is a contract that can fail (#184) |
| #265 | #265 | main | `ao/my-edotmw-80/gap-assessment` | docs: senior-gamedev gap assessment — content, onboarding, perf, product, process |
| #271 | #205 | #205 | `ao/my-edotmw-81/issue-185-steam-depot` | feat(steam): a depot upload is validated before it is authenticated (#185) |
| #272 | #250 | #263 | `ao/my-edotmw-87/one-cell-per-drawn-man` | perf(derive): one cell derivation per drawn man, not two (#245) |
| #273 | #222 | #243 | `ao/my-edotmw-86/explore-command` | Explore: a squad that hunts fog on its own until told to stop (#120) |
| #274 | #250 | #272 | `ao/my-edotmw-87/the-clamp-after-one-cell` | docs(clamp): #244 answered NO — the measurement moved under it |
| #293 | #233 | #233 | `ao/my-edotmw-88/playtest-207` | Bot playtest pass: civ differentiation across the six fantasy civs (#207) |
| #294 | #222 | #243 | `ao/my-edotmw-86/ci-pipeline` | CI: run the checks the machine can run (#290) |
| #295 | #205 | #264 | `ao/my-edotmw-79/onboarding` | feat(lobby): a civ says what it is before you pick it (#283) |
| #296 | #225 | #225 | `ao/my-edotmw-83/ladder-and-pacing` | One decision entry for the epoch ladder (#278), and a measured rate under D-068 (#281) |
| #297 | #297 | main | `ao/my-edotmw-82/surrender` | A player may concede (#279) |
| #298 | #250 | #274 | `ao/my-edotmw-87/render-cost-has-a-baseline` | feat(bench): render cost has a recorded baseline and a loud delta (#286) |
| #299 | #299 | main | `ao/my-edotmw-80/three-decisions` | Three decisions: retire islands, revisit host-quit, and guard the imported docs (#280 #289 #291) |
| #300 | #205 | #295 | `ao/my-edotmw-79/opening-hint` | feat(hud): the opening says which squad founds, from the rule the server enforces (#284) |
| #303 | #205 | #258 | `ao/my-edotmw-81/issue-288-report-a-problem` | feat(alpha): a tester can send back what happened, in one file (#288) |
| #306 | #205 | #300 | `ao/my-edotmw-79/controls-screen` | feat(ui): the controls are written down once, and say what the code does (#282) |
| #307 | #250 | #298 | `ao/my-edotmw-87/the-jostle-looks-where-the-men-are` | perf(client): the jostle looks where the men are (#262) |
| #308 | #299 | #299 | `ao/my-edotmw-80/naval-design` | Naval: the design, the pinned interface contract, AND stage 2 (water domain) — #301 |
| #310 | #250 | #307 | `ao/my-edotmw-87/every-tres-is-utf8` | fix(data): every shipped text file decodes as UTF-8 (#236) |
| #312 | #246 | #246 | `ao/my-edotmw-82/renewable-metals` | A vein runs deep: it does not run out (#277) |
| #313 | #216 | #216 | `ao/my-edotmw-81/naval-1-water-graph` | feat(naval): the water graph — navigability, shores, and water components (#301) |
| #314 | #314 | main | `ao/my-edotmw-88/naval-6-content` | Naval stage 6: the ten hulls, the dock, and the D-072 screen as tests (#301) |
| #317 | #250 | #310 | `ao/my-edotmw-87/inside-the-derive-phase` | perf(derive): attribute the phase, take the two hoists, file the rest |
| #319 | #225 | #225 | `ao/my-edotmw-83/tick-ladder` | The M6 rise has a name (#304), and separation stops over-scanning |
| #320 | #205 | #306 | `ao/my-edotmw-79/manual` | feat(manual): the manual is generated, or it is stamped (#305) |
| #321 | #321 | main | `ao/my-edotmw-82/civ-can-open` | A civ must be able to afford its own opening (#247, #275) |
| #322 | #322 | main | `ao/my-edotmw-81/issue-292-disconnect-eliminates` | fix(match): leaving a match leaves nothing behind (#292, #318) |
| #323 | #216 | #313 | `ao/my-edotmw-88/naval-3-docks` | Naval stage 3: docks — a shore rule, a water side, and hulls in the sea (#301) |
| #324 | #324 | main | `ao/my-edotmw-82/formations-granted` | Two formations that belonged to nobody (#309) |
| #326 | #250 | #317 | `ao/my-edotmw-87/inside-the-decoration-phase` | perf(client): a squad looks up its buildings, it does not walk the match (#325) |
| #327 | #216 | #313 | `ao/my-edotmw-81/naval-5-shoreline-combat` | feat(naval): melee does not cross a shoreline (#301, stage 5) |
| #328 | #328 | main | `ao/my-edotmw-82/morale-scales` | Morale is a fraction of the squad, not a count of men (#266) |
| #329 | #250 | #326 | `ao/my-edotmw-87/the-gather-stops-repeating` | perf(client): one call for a disk of cells, and a memo that did not pay |
| #330 | #330 | main | `ao/my-edotmw-82/gatherers-differ` | The crew is a civ's unit too (#269) |
| #331 | #250 | #329 | `ao/my-edotmw-87/inside-the-pipeline` | docs(perf): attribute inside the pipeline, so the remaining levers are measured |
| #333 | #216 | #323 | `ao/my-edotmw-88/naval-4-embark` | Naval stage 4: embark, disembark, and what a carried squad is (#301) |
| #334 | #334 | main | `ao/my-edotmw-82/armour-is-role` | Armour class is a role, not a flavour (#268) |
| #335 | #222 | #243 | `ao/my-edotmw-86/small-fixes` | Small-fix batch: #302 #249 #253 #254 #276 |
| #336 | #336 | main | `ao/my-edotmw-82/civ-knobs` | Four more knobs, and every one has a caller (#270) |
| #340 | #250 | #331 | `ao/my-edotmw-87/naval-8-presentation` | Naval stage 8: a rendered frame of ships on water (#301) |
| #341 | #225 | #319 | `ao/my-edotmw-83/shipping-scale` | D-018's successor number, measured: ~200 squads — and the tick at that scale with water (#287, #105) |
| #342 | #216 | #343 | `ao/my-edotmw-81/naval-7-ai-and-bots` | feat(naval): the AI sails, and a landing happens in a played match (#301, stage 7) |
| #343 | #216 | #333 | `ao/my-edotmw-88/naval-2-domain` | Naval stage 2: water is a second movement domain, with a measured budget (#301) |
| #345 | #222 | #243 | `ao/my-edotmw-86/audio-foundations` | Audio foundations: a sound is a cosmetic, and you must be able to SEE its cause (#344) |
| #347 | #334 | #334 | `ao/my-edotmw-82/levies-are-sidegrades` | fix(roster): a levy is a sidegrade, and a duel is not the test (#267) |
| #348 | #205 | #320 | `ao/my-edotmw-79/ai-fortifies` | feat(ai): an AI that fortifies, and the question naval shares with it (#337) |

---

Regenerate with `docs/plans/merge-order.gen.py`, run from the repository root. Its
three input snapshots are deliberately not committed, because they are stale the
moment a PR merges; the script's docstring carries the `gh` commands that produce
them.

---

# Merge rehearsal log

**Run 2026-08-28** on branch `rehearsal/merge-order`, which is pushed and
**must never be merged**. Every open PR was merged onto `main` in the order
published above, one at a time, recording what happened. The owner can diff
against that branch to see the combined tree.

## Headline

| outcome | PRs |
|---|---|
| merged clean | **43** |
| conflicted and resolved | **28** |
| already contained in the tree | **2** |
| could not be merged (rival implementation) | **0** |
| red on its own branch, not a merge issue | **1** |

`just test-unit` went **22 failures on `main` -> 63 on the merged tree**
(2,004 tests). Of those 63, **37 are the known native-runtime shell-out gap**
(docker/bash recipes, #223) and 26 are real. `just test-load` equivalent on the
merged tree: **VERDICT ok, 4/4 bots, 0 desyncs over 480 state-hash checks, 0
dropped ticks, 0 ticks over D-020's budget**, and all three `gate-check.sh`
comparisons green.

**The merged tree fielded 11 squads where single-PR trees fielded 32-34, and
that was a DEFECT, not the union playing differently.** An earlier version of
this page guessed it was farms, techs, civ knobs and levy costs stacking; it
was none of them. Cause found by #88 (#376): a load-test bot never sent a
produce order AT ALL — not refused, never asked, which is why no server log
ever showed a production refusal. `MatchState` seats a player with
`civ = random` and only `_on_match_started` resolves it; under `--lobby=0` a
bot connects AFTER the match begins, so its seat still reads `random`,
`for_civ_archetype` answers null, and `BotBuildPlan._resolve` treated
`random` as a real civ instead of falling back. Production was skipped
silently for the whole match.

**Re-measured on this rehearsal tree with the root fix (#380) merged in**,
same host and method:

| tree | squads | duration | squads/s | `nodes_felled` |
|---|---|---|---|---|
| single-PR baseline | 33 | 129.2 s | 0.255 | ~15-20 |
| union (as rehearsed) | 11 | 129.2 s | **0.085** | 3 |
| union + #380 | 22 | 142.3 s | **0.155** | 16 |

Casualties 37 -> 69, 0 desyncs over 476 state-hash checks, 0 dropped ticks,
0 ticks over budget. A residual gap to baseline remains and is NOT attributed
here — do not read 0.155 as "fixed", only as "most of it was this".

**The lesson worth carrying is about the instrument.** `build=` names the
CHEAPEST thing a bot currently wants, so a bot with no economy reports the
cheapest want it cannot afford. That made the farm look causal: remove farms
and the same dead bot reports `cannot afford barracks` instead, which is
exactly what a HEALTHY tree reports for an entirely different reason. **The
label discriminates cost, not health** — I ran a five-run A/B off that
reading, correctly excluded the balance cluster and #246, and still had the
wrong candidate. `nodes_felled` collapsing to 3 was the same defect wearing a
second face: with no crews there is nothing to fell.

## Five real incompatibilities, all filed

These are the point of the exercise: **every one of them is invisible on the
individual PRs**, and four of the five produce no git conflict at all.

| issue | what | how it shows up |
|---|---|---|
| **#359** | #237 adds a rule that every artifact writer goes through `ArtifactPath`; #234 adds a writer that does not | no textual conflict; one test goes red only in the union |
| **#360** | #243 and #324 both fix #309 and **disagree**: `emberdeep_heavy` gets `shield_wall` from one and `testudo` from the other | git conflicts on the one contradictory line and is silent about the other five grants |
| **#361** | the balance cluster is individually green and collectively red — 9 failures, **D-067's shipped siege rule broken** (two spearmen squads leave a town centre on 360 HP) | seven of the nine PRs merge cleanly |
| **#362** | **four** PRs claim wire opcode 39 and **two** claim 40 | #213 ships the guard that catches it, and #213 is behind three of them in the order |
| **#363** | #302 and #246 both claim keyboard `J` (`garrison_wall` vs `farm`) | `client.gd` does not parse |

Two of those (#362, #363) are the same shape: **a scarce namespace allocated by "next free value on `main`"**. Neither has a guard that can see across branches, and both produce a collision that exists only in the union.

## Corrections to the plan above

The rehearsal disproved two things this document asserted.

- **Section 1.1 overstated the #340 problem.** Naval stages 1, 3 and 4 are
  *genuine ancestors* of #340 — it legitimately builds on the naval chain
  rather than duplicating it. Merged in the published order, **#340 costs two
  trivial conflicts** (`docs/status/naval.md`, `justfile`). The "41 of 62
  files" figure was an artefact of `gh pr view --json files` reporting the
  diff against #340's *base* (the perf-chain tip), which necessarily includes
  every naval file not in that chain. Only **stage 2 (#343) is not an
  ancestor**, and that is where the real duplication is.
- **#314 and #327 are already fully contained** in the naval chain — both
  reported "nothing to merge". They are redundant PRs, which is the *stronger*
  form of section 1.2's claim.
- **The real rival implementation is #308, not #340.** #308 brings its own
  water domain against #343's: 13 conflict hunks in `squad_sim.gd`, 4 in
  `terrain_knowledge.gd`, and the divergent copy of
  `D-20260828-water-is-a-second-movement-domain.md`. The rehearsal **aborted**
  that merge rather than fabricate a resolution — the correct outcome is that
  #308 and #343 must not both land.
- **A chain is not always linear.** #243 has four children (#273, #294, #335,
  #345) which are SIBLINGS, and siblings conflict with each other exactly like
  independent stacks — the first conflict of the whole rehearsal was between
  two of them.

## What "keep both" cannot do

The rehearsal resolved mechanically wherever it could and recorded the policy
per PR. Five places where a mechanical resolution **compiles to nonsense**, all
worth knowing before hand-merging:

- **`bench_render.gd`** — no mechanical merge compiles at all. The my-edotmw-83
  and my-edotmw-87 chains both restructure it, renaming variables and changing
  `_detail_for()`'s signature. The rehearsal took the 87 chain's file wholesale
  and **lost #341's host-budget bench work**.
- **Format strings.** The load-test `VERDICT` line and the AI's `AI_STATS` line
  are each one string plus one argument array, extended by **four and three**
  different PRs. Every pair conflicts and the tails must be merged by hand.
- **Dictionaries.** `BUILD_KEYS` and the `SQUAD_INFO` decoder literal both gain
  duplicate keys under keep-both — and in the decoder's case the bytes would
  also be read in the wrong ORDER, which desynchronises every field after it.
- **`just` recipes.** Keep-both produced two `test-client` recipes, and
  interleaved `gen-seam-shot` and `gen-naval-shot` into one broken body. Two
  recipes also diverged in their **positional signature** (`bench-render` gained
  `HOST/PRESET/HULLS` on one side and `ARGS` on the other), which
  D-20260817 says silently re-points every existing invocation.
- **Refactors that delete a feature's home.** Three times a PR moved code that
  another PR's feature lived inside, so the merge is clean-looking and the
  feature is gone: #239 and then #264 each deleted the site where #232 assigns
  `_server_endpoint`, so the connection-lost screen (#162) would name an empty
  server and **nothing would fail**.

## Rulings

Decisions taken by the orchestrator on conflicts this rehearsal surfaced.
They override the per-PR table below.

### #243 vs #324 — the formation grants (#309, issue #360)

**CLOSED 2026-08-28. #324 owns the grants; #243 drops its four on its own
branch.** Settled by the authors on the merits rather than on process:
#243's grants read the units' DISPLAY NAMES, #324's read the SHIPPED
MODELS — emberdeep's levy is a shieldwarden with a round shield
(`shield_wall`), its heavy carries the kite shield (`testudo`).

**END STATE, and it is what `origin` says.** #243 at tip **`741eb68`**
("drop all four again — final arbitration"), all four grants dropped,
**#324 merges BEFORE #243**, and the merge takes **zero conflicts and
zero operator decisions** — with the four dropped, #243 makes no net
change on those lines against `origin/main`, so there is nothing for a
merger to resolve or to choose.

Verified by performing it rather than describing it: `main` → #324 →
#243 is clean at BOTH steps, and the final granted set is exactly
`emberdeep_heavy=testudo`, `emberdeep_levy=shield_wall`,
`gildedreach_spearmen=shield_wall`, with `test_fighting_styles` 6/6.

Earlier drafts of this ruling predicted "one expected conflict on
`emberdeep_heavy`, resolved #324's way". That was true of a superseded
TWO-deletion form and is **not** true of what shipped. **Any future
question about this is answered by diffing `origin`** — during the close,
a stale local `main` and a stale ruling each nearly wrote a conflict into
this record that cannot occur.

**Merge #324 BEFORE #243.** That is the whole resolution and it is free:
#324 supplies the grants first, so #243 lands with nothing to supply and
**is never itself red** — the make-main-green PR does not pass through a
state where the formations guard fails. There is then no conflict, no
merge-time deletion and no union to resolve, because the two PRs no
longer touch the same files at all.

**Why this was not a merge-time resolution, which is the part worth
keeping.** The obvious instruction — "on the conflict, take #324's side"
— reaches ONE FILE OF THREE. git conflicts only where both PRs touch the
same line, and two of #243's four grants are in files #324 never opens,
so they survive silently and the merged result is the UNION of five
granted units rather than the considered three. `assert_gt(grants, 0)`
passes at both, so green cannot tell them apart. Doing it on the branch
removes the hazard rather than documenting around it.

The five units, and why only one of them would ever have conflicted:

| unit | #324 | #243 (before the drop) | would git conflict? |
|---|---|---|---|
| `emberdeep_heavy` | `testudo` | `shield_wall` | **yes** |
| `gildedreach_spearmen` | `shield_wall` | `shield_wall` | no (identical) |
| `emberdeep_levy` | `shield_wall` | — | no |
| `gravesworn_spearmen` | — | `shield_wall` | **no — the silent pair** |
| `stoneblood_heavy` | — | `testudo` | **no — the silent pair** |

**Final granted set: #324's three** — `emberdeep_heavy=testudo`,
`emberdeep_levy=shield_wall`, `gildedreach_spearmen=shield_wall`.
Verified on a scratch merge before the branch fix was agreed: with the
two silent grants removed, merging #324 conflicts on `emberdeep_heavy`
alone and lands on exactly that set. With the drop on #243's branch and
#324 merging first, even that conflict is gone.

Worth knowing after it lands: the guard counts **`shield_wall` grantees
only**, and there is no `testudo` grantee guard at all — testudo ends with
exactly one grantee in the roster and nothing would notice if it lost it.

### #308 vs #343 — naval stage 2

**#343 wins. #308 merges DESIGN ONLY.** #308 (worker 80, now inactive)
carries a second stage-2 water-domain implementation against #343's, which
the rest of the naval chain is built on, including an add/add on a
`decisions/` path. Ruled 2026-08-28; worker 88 is commenting it on #308.

**Delete on merge.** Six items, and they divide into two kinds — the
distinction matters, because only the first kind will announce itself.

*Rivals: a second implementation of something #343 already ships. These
CONFLICT, so a merge will raise them.*

- `squad_sim.gd` — collides with 5 naval branches
- `unit_def.gd` — #308 adds its own naval fields, and so do
  naval-2/3/4/6/7. **Adopted into the ruling**: a second implementation
  one layer down is still a second implementation.
- `decisions/D-20260828-water-is-a-second-movement-domain.md` — add/add
  against #343. #343's and #340's copies are byte-identical at 9,039
  bytes and #308's is a different 9,436-byte document.
- #308's naval ENTRY in `decisions/D-010.md` — **adopted**; the schema
  log for the fields above goes with them. The REST of that file is an
  ordinary additive conflict (5 naval branches append to it): keep both.

*Orphans: #308's own code, colliding with NOTHING. A merge will not
mention these at all — they go because nothing calls them once the
rivals are removed, not because git objected.*

- `terrain_knowledge.gd` — #308's water plumbing
- `tests/test_water_domain.gd` + `.uid` — tests the deleted code

Whoever merges has to delete the orphans deliberately. That is the same
shape as the #360 resolution one section up: **a conflict-driven merge
reaches the rivals and is silent about everything else**, and the silent
half is where a rule goes quietly missing.

**Survives, beyond `docs/plans/naval.md`:** `docs/status/naval-plan.md` and
its `CLAUDE.md` import line, plus three design entries that collide with
nothing — `a-carried-squad-is-cargo`, `a-dock-stands-on-a-shore` and
`a-map-a-player-can-pick-is-a-map-an-army-can-cross`.

**Routed to #88, not a ruling:** two of those surviving entries describe
subjects the chain IMPLEMENTS — cargo is #333 and docks are #323. They do
not collide by filename, so nothing will report it if #308's design and
#343's code disagree. That is the D-058/D-065 family: a decision entry
that describes code which is not there. Read them against what shipped
before merging them.

### #222 vs #257 — the building HP

**Expected, and the only conflict inside the balance cluster.** #222 sets
`town_centre` 2400 and `tower` 1250; #257 re-derives them to 1900 and 980
because #266 and #218 together move a squad's break point from ~85%
casualties to ~52%, which invalidates the numbers D-067 was measured
against (#361). **Take #257's values.** Both files, one line each.

The cluster is otherwise CLEAN from `main` in the published order — every
conflict in the rehearsal came from #243 and waves 1-2, not from inside
it.

## Per-PR result

| PR | branch | result | notes |
|---|---|---|---|
| #222 | `ao/my-edotmw-82/d067-siege-rule` | CLEAN | 5 |
| #243 | `ao/my-edotmw-86/red-main` | CLEAN | 63 |
| #335 | `ao/my-edotmw-86/small-fixes` | CLEAN | 17 |
| #294 | `ao/my-edotmw-86/ci-pipeline` | CLEAN | 8 |
| #273 | `ao/my-edotmw-86/explore-command` | CONFLICT-RESOLVED | squad_sim.gd: siblings of #243 both add squad state and both clear it in order/stop/flee_move; kept BOTH sides in all 4 hunks |
| #345 | `ao/my-edotmw-86/audio-foundations` | CLEAN | 54 |
| #265 | `ao/my-edotmw-80/gap-assessment` | CLEAN | 1 |
| #238 | `ao/my-edotmw-81/issue-153-gate-reconciles-containers` | CONFLICT-RESOLVED | justfile + tests/test_multi_agent_isolation.gd: DUPLICATE FIX - #335 and #238 both fix #209 (--name scan matching art/attach_kit.py) with different implementations; kept #335's per-line scan, dropped #238's whole-file regex. Not additive: one must be chosen. |
| #226 | `ao/my-edotmw-81/issue-157-second-match-state` | CLEAN | 6 |
| #232 | `ao/my-edotmw-81/issue-162-disconnect-notice` | CLEAN | 5 |
| #235 | `ao/my-edotmw-87/model-preview-framing` | CLEAN | 5 |
| #237 | `ao/my-edotmw-87/artifacts-are-writable` | CLEAN | 18 |
| #234 | `ao/my-edotmw-85/playtest-visual-infra` | CLEAN | 26 |
| #251 | `ao/my-edotmw-82/ladder-instrument` | CLEAN | 6 |
| #248 | `ao/my-edotmw-82/clash-reports-its-army` | CLEAN | 9 |
| #255 | `ao/my-edotmw-80/ai-founding-and-gates` | CONFLICT-RESOLVED | docs/status/{ai-opponent,playtests-2026-08}.md: two PRs appending sections at the same point; kept BOTH. Trivial, and the shape CLAUDE.md predicts for status docs. |
| #322 | `ao/my-edotmw-81/issue-292-disconnect-eliminates` | CONFLICT-RESOLVED | docs/status/playtests-2026-08.md: third PR appending at the same point; kept BOTH. Trivial. |
| #221 | `ao/my-edotmw-82/lod-hysteresis` | CLEAN | 6 |
| #252 | `ao/my-edotmw-82/d067-garrison` | CLEAN | 3 |
| #260 | `ao/my-edotmw-82/d072-screen` | CLEAN | 3 |
| #261 | `ao/my-edotmw-82/counters-are-felt` | CLEAN | 3 |
| #321 | `ao/my-edotmw-82/civ-can-open` | CLEAN | 3 |
| #324 | `ao/my-edotmw-82/formations-granted` | RULED-#324-FIRST | CLOSED #360, end state = origin tip 741eb68: all four grants dropped, #324 merges BEFORE #243, ZERO conflicts and ZERO operator decisions (with four dropped #243 makes no net change on those lines against origin/main). Verified by performing it: main -> #324 -> #243 is CLEAN at both steps, final set emberdeep_heavy=testudo, emberdeep_levy=shield_wall, gildedreach_spearmen=shield_wall, test_fighting_styles 6/6. Old note below described the superseded two-deletion form. |
| #330 | `ao/my-edotmw-82/gatherers-differ` | CONFLICT-RESOLVED | all six units/*_gatherers.tres: DUPLICATE FIX - #243 also differentiates the gatherers (#269) with different numbers. Took #330's values (the dedicated PR, which carries the decision entry and the guard). Third instance of #243 duplicating a dedicated PR. |
| #334 | `ao/my-edotmw-82/armour-is-role` | CLEAN | 6 |
| #347 | `ao/my-edotmw-82/levies-are-sidegrades` | CLEAN | 10 |
| #328 | `ao/my-edotmw-82/morale-scales` | CLEAN | 6 |
| #257 | `ao/my-edotmw-82/fortifications-frighten` | CLEAN | 5 |
| #297 | `ao/my-edotmw-82/surrender` | CONFLICT-RESOLVED | building_sim.gd: DUPLICATE - #322 and #297 both add BuildingSim.eliminate_player, semantically identical (same signature, same damage(i,INF) loop, both citing #292 and D-033). Kept HEAD's (#322's). Fourth duplicate-fix pair found. |
| #336 | `ao/my-edotmw-82/civ-knobs` | CLEAN | 13 |
| #233 | `ao/my-edotmw-84/playtest-bot-findings` | CONFLICT-RESOLVED | docs/playtests/README.md: index file appended by several PRs; kept BOTH. Trivial. |
| #293 | `ao/my-edotmw-88/playtest-207` | SINGLE-PR-RED | adds playtest_obs/obs_civs.gd which names civ ids; tests/test_civs.gd EXEMPT_PREFIXES is only tests/ and addons/, and #293 does not touch that test -> test_no_script_mentions_a_civ_id is red on its OWN branch (D-046 criterion 3). Not a merge issue. |
| #299 | `ao/my-edotmw-80/three-decisions` | CLEAN | 15 |
| #225 | `ao/my-edotmw-83/tech-tree` | CONFLICT-RESOLVED | net_protocol.gd: WIRE OPCODE COLLISION - C2S_SURRENDER(#297), C2S_ORDER_EXPLORE(#273) and C2S_ORDER_RESEARCH(#225) ALL claim opcode 39. Renumbered explore=41, research=42 to continue. civ_def.gd: additive fields, kept both. |
| #296 | `ao/my-edotmw-83/ladder-and-pacing` | CLEAN | 15 |
| #319 | `ao/my-edotmw-83/tick-ladder` | CLEAN | 8 |
| #341 | `ao/my-edotmw-83/shipping-scale` | CLEAN | 8 |
| #250 | `ao/my-edotmw-87/render-cost-attribution` | CONFLICT-RESOLVED | justfile: bench-render POSITIONAL SIGNATURE diverged - one PR adds HOST/PRESET/HULLS, #250 adds ARGS. Combined into one signature. D-20260817 says just args are positional, so two signatures for one recipe silently re-points every invocation. bench_render.gd: 5 additive hunks, kept both. |
| #263 | `ao/my-edotmw-87/bench-is-the-client` | CONFLICT-RESOLVED | bench_render.gd: CROSS-CHAIN - my-edotmw-83 (#341 host budgets, #339) and my-edotmw-87 (#250/#263 render attribution) both restructure the benchmark. Kept both; the 87 chain re-conflicts on this file at every step. |
| #272 | `ao/my-edotmw-87/one-cell-per-drawn-man` | CLEAN | 11 |
| #274 | `ao/my-edotmw-87/the-clamp-after-one-cell` | CLEAN | 4 |
| #298 | `ao/my-edotmw-87/render-cost-has-a-baseline` | CLEAN | 12 |
| #307 | `ao/my-edotmw-87/the-jostle-looks-where-the-men-are` | CONFLICT-RESOLVED | client.gd: REFACTOR vs ADDITION - #307 replaces _drawn_cache with a DrawnIndex, while #221 (lod-hysteresis) adds _lod_tier beside it. 'Keep both' would call .clear() on a variable #307 deleted; kept _drawn.begin() + _lod_tier.clear(). One stale doc-comment reference to _drawn_cache survives at client.gd:207. |
| #310 | `ao/my-edotmw-87/every-tres-is-utf8` | CLEAN | 9 |
| #317 | `ao/my-edotmw-87/inside-the-derive-phase` | CLEAN | 5 |
| #326 | `ao/my-edotmw-87/inside-the-decoration-phase` | CLEAN | 9 |
| #329 | `ao/my-edotmw-87/the-gather-stops-repeating` | CLEAN | 6 |
| #331 | `ao/my-edotmw-87/inside-the-pipeline` | CLEAN | 3 |
| #205 | `ao/my-edotmw-79/export` | CLEAN | 15 |
| #213 | `ao/my-edotmw-79/handshake` | CONFLICT-RESOLVED | bot_client.gd: the load-test VERDICT line is extended by THREE PRs - #248 (_scenario), #225 (techs_ordered/techs_held) and #213 (refused). Format string and its argument array both conflict; merged all three tails by hand. Mechanically resolvable but not by any keep-ours/keep-theirs rule. |
| #239 | `ao/my-edotmw-79/main-menu` | CONFLICT-RESOLVED | client.gd: REFACTOR DEFEATS A FEATURE - #239 moves the connect out of _ready() into _connect_to(), deleting the site where #232 assigns _server_endpoint. #239's branch has ZERO references to it. Merged naively the connection-lost screen (#162) shows an empty endpoint and NOTHING fails. Re-attached the assignment inside _connect_to. justfile: additive recipes, kept both. |
| #242 | `ao/my-edotmw-79/steam-boundary` | CLEAN | 9 |
| #256 | `ao/my-edotmw-79/host-in-process` | CONFLICT-RESOLVED | server.gd 4 hunks: #256 (_local_clients / in-process host) vs #226 (_fresh_record, _recipients()) and #336 (_civ_effects_for). Took HEAD throughout - _recipients() already merges _local_clients and _fresh_record generalises #256's key-by-key clearing, so the newer refactors subsume #256's versions. #256's explanatory comment about the recipients drift is lost. |
| #258 | `ao/my-edotmw-79/alpha-loop` | CLEAN | 8 |
| #264 | `ao/my-edotmw-79/steam-transport` | CONFLICT-RESOLVED | client.gd + server.gd: REFACTOR DEFEATS A FEATURE (2nd time for the same feature) - #264 replaces ENetConnection with a NetTransport seam, deleting BOTH the _host field and the connect site. #232's #162 disconnect handling and _server_endpoint had to be re-attached again, on top of the same re-attachment #239 already forced. server.gd: _host.destroy() -> _transport.close(), keeping #237's replay print. |
| #295 | `ao/my-edotmw-79/onboarding` | CONFLICT-RESOLVED | all six civs/*.tres: additive - #295 adds signature_unit alongside #336's knobs; kept both. This is the 5-chain civs/*.tres contention the merge plan predicted. |
| #300 | `ao/my-edotmw-79/opening-hint` | CONFLICT-RESOLVED | justfile: SECOND positional-signature divergence - test-client is RESOLUTION="1280x720" on one side and HOLD="0" on the other. A keep-both resolution produces TWO test-client recipes and just refuses the file; combined into one signature. Same trap as bench-render (#250). |
| #306 | `ao/my-edotmw-79/controls-screen` | CLEAN | 9 |
| #320 | `ao/my-edotmw-79/manual` | CONFLICT-RESOLVED | client.gd: additive doc/table block (#302 keyboard-letter registry); kept both. |
| #348 | `ao/my-edotmw-79/ai-fortifies` | CONFLICT-RESOLVED | ai_player.gd (4 hunks) + bot_client.gd (3): keep-both does NOT compile. AI_STATS and the load-test VERDICT are each a single format string + arg array extended by FOUR different PRs (#248 scenario, #225 techs, #348 gates, #213 refused); every pair conflicts and the tails must be merged by hand. Also a real semantic merge in the AI building loop: #225 filters per-civ and by tech, #348 excludes wall-like/damaging defs - both filters are needed. |
| #271 | `ao/my-edotmw-81/issue-185-steam-depot` | CONFLICT-RESOLVED | CLAUDE.md (status-doc @import list) + justfile (doctor block): both additive; kept both. CLAUDE.md's import list conflicts on nearly every PR that adds a status doc - 8 chains touch it. |
| #246 | `ao/my-edotmw-88/renewable-food` | CONFLICT-RESOLVED | 12 files. REAL: KEYBINDING COLLISION - #302 (in #243/#335) moves garrison_wall to J, #246 independently assigns J to farm; both checked J against the tables as they stood on main. Moved farm to O. Also bot_client.gd gather loop rewritten by #246 (took theirs) and the VERDICT/BOT lines extended by a FIFTH pair of counters; ai/*.tres and civs/*.tres additive. |
| #303 | `ao/my-edotmw-81/issue-288-report-a-problem` | CONFLICT-RESOLVED | client.gd: two PRs adding buttons to the same ESC menu column (#297 Surrender, #303 Report a problem); additive, kept both. |
| #312 | `ao/my-edotmw-82/renewable-metals` | CLEAN | 5 |
| #216 | `ao/my-edotmw-80/map-spawn-fixes` | CONFLICT-RESOLVED | two status docs appended by several PRs; kept both. Trivial. |
| #313 | `ao/my-edotmw-81/naval-1-water-graph` | CLEAN | 8 |
| #323 | `ao/my-edotmw-88/naval-3-docks` | CONFLICT-RESOLVED | server.gd: same add_building() call extended by two PRs - #336 adds a civ build_time argument, #323 adds a following water-side block. Both kept. decisions/D-010.md: the schema log is appended by every PR adding a field (naval, #328, #336) - kept both. |
| #333 | `ao/my-edotmw-88/naval-4-embark` | CONFLICT-RESOLVED | net_protocol.gd/client_state.gd/squad_sim.gd: SQUAD_INFO extended by two PRs at once - #273 adds an 'exploring' byte, #333 adds a variable-length 'cargo' block. Keep-both duplicated the decoder's files/stance keys AND would have read the bytes in the wrong order; hand-merged to files->stance->exploring->cargo to match the encoder. A wire-order mistake here desyncs every field after it. |
| #343 | `ao/my-edotmw-88/naval-2-domain` | CONFLICT-RESOLVED | squad_sim.gd: #343 replaces _tier_for_destination with _wanted_domain_for at a line where #273 clears _explore; keep-both declared wanted_tier twice. Kept the explore clear plus #343's domain call. |
| #342 | `ao/my-edotmw-81/naval-7-ai-and-bots` | CONFLICT-RESOLVED | ai_player.gd: AI_STATS extended a THIRD time (ladder #225, fortify #348, naval #342) - format string and arg array hand-merged again. ai_profile.gd and gate-check.sh additive. |
| #327 | `ao/my-edotmw-81/naval-5-shoreline-combat` | ALREADY |  |
| #314 | `ao/my-edotmw-88/naval-6-content` | ALREADY |  |
| #308 | `ao/my-edotmw-80/naval-design` | RULED-DESIGN-ONLY | ORCHESTRATOR RULING 2026-08-28: #343 wins stage 2. #308 merges DESIGN ONLY. Delete on merge: squad_sim.gd, terrain_knowledge.gd, tests/test_water_domain.gd(+.uid), decisions/D-20260828-water-is-a-second-movement-domain.md (add/add against #343), plus (ADOPTED into the ruling 2026-08-28) unit_def.gd (rival naval fields, collides with 5 naval branches) and #308's naval entry in decisions/D-010.md. RIVALS conflict and a merge will raise them; terrain_knowledge.gd and test_water_domain.gd are ORPHANS that collide with nothing and must be deleted deliberately. Survives: docs/plans/naval.md, docs/status/naval-plan.md + its CLAUDE.md import, and the three design entries a-carried-squad-is-cargo / a-dock-stands-on-a-shore / a-map-a-player-can-pick-is-a-map-an-army-can-cross. |
| #340 | `ao/my-edotmw-87/naval-8-presentation` | CONFLICT-RESOLVED | docs/status/naval.md additive. justfile: a keep-both INTERLEAVED two distinct recipes (gen-seam-shot from #234 and gen-naval-shot from #340) into one broken body - just refused the file; had to lift #340's recipe out whole and append it. CORRECTION to the merge plan: naval stages 1/3/4 ARE genuine ancestors of #340, so it is NOT a duplicate of the naval chain - once that chain is merged first, #340 costs two trivial conflicts. Only stage 2 (#343) is not an ancestor. |

**bench_render.gd (HAND-MERGE-REQUIRED):** NO mechanical merge of bench_render.gd compiles: my-edotmw-83 (#339/#341 host budgets) and my-edotmw-87 (#250-#331 render attribution) both restructure it, renaming variables (target) and changing _detail_for()'s signature. Keeping both sides gives 3 parse errors. Rehearsal took the 87 chain's file wholesale, LOSING #341's host-budget bench work.

