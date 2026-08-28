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

`decisions/D-20260828-water-is-a-second-movement-domain.md` exists on three
branches: #343 and #340 are identical at 9,039 bytes, and **#308's is a
different document at 9,436 bytes**. The project's rule is one file per decision
and never a renumber, so this needs the authors to reconcile it, not a merge
resolution. `D-20260828-the-water-graph-is-the-inverse-of-the-ground.md` is
likewise in both #313 and #340.

## 2. Recommended first five merges

| # | PR | branch | why this one first |
|---|---|---|---|
| 1 | #222 | `ao/my-edotmw-82/d067-siege-rule` | the D-067 re-derivation the whole balance cluster sits behind, and #243/#252 are stacked on it |
| 2 | #243 | `ao/my-edotmw-86/red-main` | makes `test-unit` green and the docker estate runnable; four PRs are stacked on it and nothing else can be tested honestly until it lands |
| 3 | #265 | `ao/my-edotmw-80/gap-assessment` | one file, docs only — zero conflict surface |
| 4 | #238 | `ao/my-edotmw-81/issue-153-gate-reconciles-containers` | `justfile` only, no shipped code |
| 5 | #226 | `ao/my-edotmw-81/issue-157-second-match-state` | six files, `server.gd` only, self-contained |

#222 then #243 is both the orchestrator's directive and what the graph
requires.

## 3. Merge order

Within a chain the order is forced — parent before child. Between chains, the
order below puts the chain that OWNS a contended file ahead of the chains that
merely touch it, so the later ones rebase onto a settled version.

### Wave 1 — make main green

Blocking, and strictly in this order: #243 is stacked on #222, and #273/#294/#335/#345 are all stacked on #243. Nothing else in the queue can be tested honestly until #243 lands.

| order | PR | base | branch | what it is |
|---|---|---|---|---|
| 1 | #222 | main | `ao/my-edotmw-82/d067-siege-rule` | Re-derive D-067's numbers, and ask the pair rule of LINE troops (#152) |
| 2 | #243 | #222 | `ao/my-edotmw-86/red-main` | Make test-unit green and the docker estate runnable again (#223, #215, #208, #209) |
| 3 | #335 | #243 | `ao/my-edotmw-86/small-fixes` | Small-fix batch: #302 #249 #253 #254 #276 |
| 4 | #294 | #243 | `ao/my-edotmw-86/ci-pipeline` | CI: run the checks the machine can run (#290) |
| 5 | #273 | #243 | `ao/my-edotmw-86/explore-command` | Explore: a squad that hunts fog on its own until told to stop (#120) |
| 6 | #345 | #243 | `ao/my-edotmw-86/audio-foundations` | Audio foundations: a sound is a cosmetic, and you must be able to SEE its cause (#344) |

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
| 6 | #324 | main | `ao/my-edotmw-82/formations-granted` | Two formations that belonged to nobody (#309) |
| 7 | #330 | main | `ao/my-edotmw-82/gatherers-differ` | The crew is a civ's unit too (#269) |
| 8 | #334 | main | `ao/my-edotmw-82/armour-is-role` | Armour class is a role, not a flavour (#268) |
| 9 | #347 | #334 | `ao/my-edotmw-82/levies-are-sidegrades` | fix(roster): a levy is a sidegrade, and a duel is not the test (#267) |
| 10 | #328 | main | `ao/my-edotmw-82/morale-scales` | Morale is a fraction of the squad, not a count of men (#266) |
| 11 | #257 | main | `ao/my-edotmw-82/fortifications-frighten` | A fortification frightens men: no morale recovery under fire (#218) |
| 12 | #297 | main | `ao/my-edotmw-82/surrender` | A player may concede (#279) |
| 13 | #336 | main | `ao/my-edotmw-82/civ-knobs` | Four more knobs, and every one has a caller (#270) |

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
