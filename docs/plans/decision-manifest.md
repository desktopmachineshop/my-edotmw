# Decision manifest — which PR each entry's code is waiting in

**Generated** by `docs/plans/decisions-ahead.gen.py` (#364), from
`origin/main` and the open PR queue. **Re-run it rather than trusting
it** — every row below is stale the moment a PR merges.

`decisions/` on `main` held **160** entries before this branch; it holds
**229** after. The 69 added ones describe code that is **not on `main`**
yet. This table is the only thing that says so, which is why it exists:
read an entry, then check here before assuming its code is in the game.

| entry | code waits in | PR title |
|---|---|---|
| `D-20260827-a-buildings-hp-is-one-knob-and-the-rule-needs-two.md` | **#222** #243 #252 #273 #294 #335 (+3) | Re-derive D-067's numbers, and ask the pair rule of LINE troops (#152) |
| `D-20260827-a-client-record-forgets-the-match-it-left.md` | **#226** | fix(server): a client record forgets the match it left (#157) |
| `D-20260827-a-client-starts-before-it-connects.md` | **#239** #242 #256 #258 #264 #295 (+7) | feat(client): a client starts before it connects, and lands back on a  |
| `D-20260827-a-client-with-no-server-says-so.md` | **#232** | feat(client): a client with no server says so (#162) |
| `D-20260827-a-lod-tier-is-sticky.md` | **#221** | A LOD tier is sticky, and the distance it reads is a minimum (#155) |
| `D-20260827-a-research-site-is-a-building.md` | **#225** #296 #319 #341 #358 | The civ tech tree: buildings research techs, and completing the defini |
| `D-20260827-every-start-shares-one-landmass.md` | **#216** #313 #323 #327 #333 #340 (+4) | fix(map/hud): every start shares one landmass; minimap clicks read the |
| `D-20260827-the-build-is-exported-from-one-version.md` | **#205** #213 #239 #242 #256 #258 (+10) | feat(build): just export produces the shipping builds from one version |
| `D-20260827-the-gate-charges-work-not-launchers.md` | **#238** | fix(gate): charge the work, not the launcher (#153) |
| `D-20260827-the-join-flow-carries-a-protocol-version.md` | **#213** #239 #242 #256 #258 #264 (+8) | feat(net): the join flow carries a protocol version, and a stale build |
| `D-20260827-the-tree-is-the-ladder.md` | **#296** | One decision entry for the epoch ladder (#278), and a measured rate un |
| `D-20260828-a-carried-squad-is-cargo.md` | **#308** | Naval: the design, the pinned interface contract, AND stage 2 (water d |
| `D-20260828-a-civ-must-be-able-to-afford-its-own-opening.md` | **#321** | A civ must be able to afford its own opening (#247, #275) |
| `D-20260828-a-civ-says-what-it-is-before-you-pick-it.md` | **#295** #300 #306 #320 #348 #357 | feat(lobby): a civ says what it is before you pick it (#283) |
| `D-20260828-a-depot-upload-is-validated-before-it-is-authenticated.md` | **#271** | feat(steam): a depot upload is validated before it is authenticated (# |
| `D-20260828-a-dock-stands-on-a-shore.md` | **#308** | Naval: the design, the pinned interface contract, AND stage 2 (water d |
| `D-20260828-a-fight-is-decided-by-two-percent.md` | **#355** | docs(combat): a fight is decided by two percent — measure it, ship not |
| `D-20260828-a-fortification-frightens-men.md` | **#257** | A fortification frightens men: no morale recovery under fire (#218) |
| `D-20260828-a-game-is-found-not-typed.md` | **#354** | A game is FOUND, not typed: a provider-based game browser (#187) |
| `D-20260828-a-guard-is-written-in-a-vocabulary-that-moves.md` | **#243** #273 #294 #335 #345 #356 (+1) | Make test-unit green and the docker estate runnable again (#223, #215, |
| `D-20260828-a-harness-asserts-the-match-ended.md` | **#251** | The ladder asserts the match ENDED, and a decided one stops (#224) |
| `D-20260828-a-hull-is-drawn-on-the-sea.md` | **#340** #353 | Naval stage 8: a rendered frame of ships on water (#301) |
| `D-20260828-a-levy-is-a-sidegrade-and-a-duel-is-not-the-test.md` | **#347** #355 | fix(roster): a levy is a sidegrade, and a duel is not the test (#267) |
| `D-20260828-a-map-a-player-can-pick-is-a-map-an-army-can-cross.md` | **#308** | Naval: the design, the pinned interface contract, AND stage 2 (water d |
| `D-20260828-a-player-may-concede.md` | **#297** | A player may concede (#279) |
| `D-20260828-a-report-is-made-not-sent.md` | **#303** | feat(alpha): a tester can send back what happened, in one file (#288) |
| `D-20260828-a-scenarios-gates-are-what-it-contains.md` | **#248** | A scenario's gates are what that scenario contains (#230) |
| `D-20260828-a-seat-belongs-to-a-person-not-a-socket.md` | **#356** | Archetype vocabulary (#332) and seat identity / repossession (#186 eng |
| `D-20260828-a-sound-is-a-cosmetic-you-must-be-able-to-see.md` | **#345** | Audio foundations: a sound is a cosmetic, and you must be able to SEE  |
| `D-20260828-a-squad-looks-up-its-buildings.md` | **#353** #331 #340 | Naval integration verification: the nine-stage chain run as one thing  |
| `D-20260828-a-summary-is-shown-or-it-is-deleted.md` | **#246** #312 | Food is GROWN, not only found: the farm (#159), plus two .tres cleanup |
| `D-20260828-a-transport-is-a-seam-and-ordering-is-the-contract.md` | **#264** #295 #300 #306 #320 #348 (+1) | feat(net): a transport is a seam, and ordering is a contract that can  |
| `D-20260828-a-vein-runs-deep-it-does-not-run-out.md` | **#312** | A vein runs deep: it does not run out (#277) |
| `D-20260828-an-ai-invests-in-what-it-cannot-walk-to.md` | **#342** #353 | feat(naval): the AI sails, and a landing happens in a played match (#3 |
| `D-20260828-an-ai-that-fortifies.md` | **#348** #357 | feat(ai): an AI that fortifies, and the question naval shares with it  |
| `D-20260828-an-imported-doc-names-the-code-it-is-about.md` | **#299** #308 | Three decisions: retire islands, revisit host-quit, and guard the impo |
| `D-20260828-armour-class-is-a-role-not-a-flavour.md` | **#334** #347 #355 | Armour class is a role, not a flavour (#268) |
| `D-20260828-artifacts-are-written-where-the-build-can-write.md` | **#237** #303 | fix(artifacts): write where the build can write, and say where that is |
| `D-20260828-d067-is-a-rush-rule-and-a-rush-has-no-garrison.md` | **#252** | D-067 is a rush rule, and a rush has no garrison (#227) |
| `D-20260828-every-microsecond-of-a-frame-has-a-phase.md` | **#353** #272 #274 #298 #307 #310 (+5) | Naval integration verification: the nine-stage chain run as one thing  |
| `D-20260828-explore-is-an-order-and-the-frontier-is-knowledge.md` | **#273** | Explore: a squad that hunts fog on its own until told to stop (#120) |
| `D-20260828-food-is-grown-not-only-found.md` | **#246** #312 | Food is GROWN, not only found: the farm (#159), plus two .tres cleanup |
| `D-20260828-four-more-knobs-and-every-one-has-a-caller.md` | **#336** | Four more knobs, and every one has a caller (#270) |
| `D-20260828-godotsteam-does-not-ship-a-gdextension.md` | **#242** #256 #258 #264 #295 #300 (+6) | feat(steam): one script names Steam, and a test makes that structural  |
| `D-20260828-host-quit-is-priced-against-a-match-length-nobody-has-measured.md` | **#299** #308 | Three decisions: retire islands, revisit host-quit, and guard the impo |
| `D-20260828-inside-the-derive-phase.md` | **#317** #326 #329 #331 #340 #353 | perf(derive): attribute the phase, take the two hoists, file the rest |
| `D-20260828-leaving-a-match-leaves-nothing-behind.md` | **#322** | fix(match): leaving a match leaves nothing behind (#292, #318) |
| `D-20260828-melee-does-not-cross-a-shoreline.md` | **#327** #342 #353 | feat(naval): melee does not cross a shoreline (#301, stage 5) |
| `D-20260828-morale-is-a-fraction-of-the-squad.md` | **#328** | Morale is a fraction of the squad, not a count of men (#266) |
| `D-20260828-one-armour-class-is-doing-all-the-work.md` | **#261** | The counter triangle is measured, and one armour class is doing all th |
| `D-20260828-render-cost-has-a-recorded-baseline.md` | **#298** #307 #310 #317 #326 #329 (+3) | feat(bench): render cost has a recorded baseline and a loud delta (#28 |
| `D-20260828-the-alpha-loop-is-a-zip-and-a-runbook.md` | **#258** #264 #295 #300 #303 #306 (+3) | feat(alpha): a versioned zip, a runbook, and the page a tester reads ( |
| `D-20260828-the-benchmark-runs-the-clients-own-render-pipeline.md` | **#263** #272 #274 #298 #307 #310 (+6) | perf(bench): the benchmark runs the client's own render pipeline (#240 |
| `D-20260828-the-clamp-stays-per-man.md` | **#274** #298 #307 #310 #317 #326 (+4) | docs(clamp): #244 answered NO — the measurement moved under it |
| `D-20260828-the-controls-are-written-down-once.md` | **#306** #320 #348 #357 | feat(ui): the controls are written down once, and say what the code do |
| `D-20260828-the-crew-is-a-civs-unit-too.md` | **#330** | The crew is a civ's unit too (#269) |
| `D-20260828-the-epoch-ladder.md` | **#296** | One decision entry for the epoch ladder (#278), and a measured rate un |
| `D-20260828-the-host-pays-both-budgets.md` | **#341** #358 | The shipping scale, measured — ~200 squads dedicated, 100-150 hosted ( |
| `D-20260828-the-host-runs-the-server-inside-its-own-client.md` | **#256** #258 #264 #295 #300 #303 (+5) | feat(host): the host runs the server inside its own client (#182) |
| `D-20260828-the-import-ceiling-is-the-whole-estates-ceiling.md` | **#243** #273 #294 #335 #345 #356 (+1) | Make test-unit green and the docker estate runnable again (#223, #215, |
| `D-20260828-the-jostle-looks-where-the-men-are.md` | **#307** #310 #317 #326 #329 #331 (+2) | perf(client): the jostle looks where the men are (#262) |
| `D-20260828-the-m6-rise-has-a-name.md` | **#319** #341 #358 | The M6 rise has a name (#304), and separation stops over-scanning |
| `D-20260828-the-manual-is-generated-or-it-is-stamped.md` | **#320** #348 #357 | feat(manual): the manual is generated, or it is stamped (#305) |
| `D-20260828-the-opening-says-which-squad-founds.md` | **#300** #306 #320 #348 #357 | feat(hud): the opening says which squad founds, from the rule the serv |
| `D-20260828-the-phase-table-has-numbers.md` | **#296** | One decision entry for the epoch ladder (#278), and a measured rate un |
| `D-20260828-the-power-budget-is-a-screen-with-a-known-blind-spot.md` | **#260** | D-072's screen is runnable, and every violation is in its blind spot ( |
| `D-20260828-the-shipping-scale.md` | **#341** #358 | The shipping scale, measured — ~200 squads dedicated, 100-150 hosted ( |
| `D-20260828-the-water-graph-is-the-inverse-of-the-ground.md` | **#313** #323 #327 #333 #340 #342 (+3) | feat(naval): the water graph — navigability, shores, and water compone |
| `D-20260828-two-formations-that-belonged-to-nobody.md` | **#324** | Two formations that belonged to nobody (#309) |

## Deliberately NOT landed — two authors, different bytes

These entries exist on several branches with **different content**,
and the branches are not related by history — so this is two people
writing different things under one ID, not an amendment. A script
must not pick. **A missing entry is visible; a wrong one is not.**

- `D-20260828-water-is-a-second-movement-domain.md`
  - `e76127723e` in #340, #342, #343, #352, #353
  - `85ea49fc29` in #308

## Deliberately NOT landed — amendments to entries already on `main`

An amendment edits a file `main` already has, so landing it early
turns a silent add/add into a real conflict on every PR that
carries it. That is the opposite of this branch's whole premise.

- `decisions/D-018.md` — amended by #205, #213, #216, #221, #222, #225, #226, #232, #233, #234, #235, #237, #238, #239, #242, #243, #246, #248, #250, #251, #252, #255, #256, #257, #258, #260, #261, #263, #264, #265, #271, #272, #273, #274, #293, #294, #295, #296, #297, #298, #299, #300, #303, #306, #307, #308, #310, #312, #313, #314, #317, #319, #320, #321, #322, #323, #324, #326, #327, #328, #329, #330, #331, #333, #334, #335, #336, #340, #341, #342, #343, #345, #347, #348, #350, #352, #353, #354, #355, #356, #357, #358, #368
- `decisions/D-069-the-epoch-ladder-five-rungs-antiquity.md` — amended by #205, #213, #216, #221, #222, #225, #226, #232, #233, #234, #235, #237, #238, #239, #242, #243, #246, #248, #250, #251, #252, #255, #256, #257, #258, #260, #261, #263, #264, #265, #271, #272, #273, #274, #293, #294, #295, #296, #297, #298, #299, #300, #303, #306, #307, #308, #310, #312, #313, #314, #317, #319, #320, #321, #322, #323, #324, #326, #327, #328, #329, #330, #331, #333, #334, #335, #336, #340, #341, #342, #343, #345, #347, #348, #350, #352, #353, #354, #355, #356, #357, #358, #368
- `decisions/D-20260818-a-soldier-stands-where-his-squad-could-walk.md` — amended by #205, #213, #216, #221, #222, #225, #226, #232, #233, #234, #235, #237, #238, #239, #242, #243, #246, #248, #250, #251, #252, #255, #256, #257, #258, #260, #261, #263, #264, #265, #271, #272, #273, #274, #293, #294, #295, #296, #297, #298, #299, #300, #303, #306, #307, #308, #310, #312, #313, #314, #317, #319, #320, #321, #322, #323, #324, #326, #327, #328, #329, #330, #331, #333, #334, #335, #336, #340, #341, #342, #343, #345, #347, #348, #350, #352, #353, #354, #355, #356, #357, #358, #368
- `decisions/D-20260823-fantasy-civs-on-a-four-epoch-ladder.md` — amended by #205, #213, #216, #221, #222, #225, #226, #232, #233, #234, #235, #237, #238, #239, #242, #243, #246, #248, #250, #251, #252, #255, #256, #257, #258, #260, #261, #263, #264, #265, #271, #272, #273, #274, #293, #294, #295, #296, #297, #298, #299, #300, #303, #306, #307, #308, #310, #312, #313, #314, #317, #319, #320, #321, #322, #323, #324, #326, #327, #328, #329, #330, #331, #333, #334, #335, #336, #340, #341, #342, #343, #345, #347, #348, #350, #352, #353, #354, #355, #356, #357, #358, #368
- `decisions/OPEN-QUESTIONS.md` — amended by #205, #213, #216, #221, #222, #225, #226, #232, #233, #234, #235, #237, #238, #239, #242, #243, #246, #248, #250, #251, #252, #255, #256, #257, #258, #260, #261, #263, #264, #265, #271, #272, #273, #274, #293, #294, #295, #296, #297, #298, #299, #300, #303, #306, #307, #308, #310, #312, #313, #314, #317, #319, #320, #321, #322, #323, #324, #326, #327, #328, #329, #330, #331, #333, #334, #335, #336, #340, #341, #342, #343, #345, #347, #348, #350, #352, #353, #354, #355, #356, #357, #358, #368
- `decisions/README.md` — amended by #205, #213, #216, #221, #222, #225, #226, #232, #233, #234, #235, #237, #238, #239, #242, #243, #246, #248, #250, #251, #252, #255, #256, #257, #258, #260, #261, #263, #264, #265, #271, #272, #273, #274, #293, #294, #295, #296, #297, #298, #299, #300, #303, #306, #307, #308, #310, #312, #313, #314, #317, #319, #320, #321, #322, #323, #324, #326, #327, #328, #329, #330, #331, #333, #334, #335, #336, #340, #341, #342, #343, #345, #347, #348, #350, #352, #353, #354, #355, #356, #357, #358, #368

## The schema log is #368's, whole

`decisions/D-010.md` and every `D-010-schema-*.md` is **held back**
deliberately. #364 was written asking for the schema-log append too,
and at the time that was right: six PRs were appending to one monolith
and somebody had to union them. **#368 opened while this branch was
being built** and does the structural fix instead (#366) — `D-010.md`
becomes an index and the entries move to
`D-010-schema-{units,buildings,civs,techs,naval,audio}.md`.

Unioning a file that is about to be split is work thrown away that also
conflicts with the fix. And landing #368's six new files *without* its
restructured index would leave six entries nothing points to, with
`D-010.md` still a monolith. **A restructure is atomic, and
half-applying somebody else's is worse than not applying it.**

The six appends waiting on it: #308 and the #314/#323/#333 naval
chain, #246 and #312 (the farm and renewable metals), #336 (four more
civ knobs).

**#367 came out of looking at them together.** `UnitDef.movement_domain`
is logged twice with different defaults — `ground` by two implementing
chains and `land` by #308, the design PR — because two chains defined
one field without seeing each other. Putting the log in one place is
what made it visible, which is this branch's whole argument in one
field name.

