# -*- coding: utf-8 -*-
"""Turns rehearsal.tsv into the log appended to docs/plans/merge-order.md."""
import io, collections

rows = []
for line in io.open('rehearsal.tsv', encoding='utf-8', newline=''):
    line = line.rstrip('\n')
    if not line:
        continue
    parts = line.split('\t')
    while len(parts) < 4:
        parts.append('')
    rows.append(parts[:4])

# One status per PR: a later, more specific row wins.
RANK = {'RULED-DESIGN-ONLY': 4,
        'CLEAN': 0, 'ALREADY': 0, 'CONFLICT': 1, 'CONFLICT-RESOLVED': 2,
        'HAND-MERGE-REQUIRED': 3, 'INCOMPATIBLE-NOT-MERGED': 3,
        'SINGLE-PR-RED': 3, 'MISSING': 3}
best = {}
order = []
for pr, head, status, note in rows:
    if pr not in best:
        order.append(pr)
    cur = best.get(pr)
    if cur is None or RANK.get(status, 0) >= RANK.get(cur[1], 0):
        best[pr] = (head, status, note if note else (cur[2] if cur else ''))

tally = collections.Counter(v[1] for v in best.values())
o = io.StringIO()
w = o.write

w('\n---\n\n')
w('# Merge rehearsal log\n\n')
w('**Run 2026-08-28** on branch `rehearsal/merge-order`, which is pushed and\n')
w('**must never be merged**. Every open PR was merged onto `main` in the order\n')
w('published above, one at a time, recording what happened. The owner can diff\n')
w('against that branch to see the combined tree.\n\n')
w('## Headline\n\n')
n_clean = tally.get('CLEAN', 0) + tally.get('ALREADY', 0)
n_conf = tally.get('CONFLICT-RESOLVED', 0) + tally.get('CONFLICT', 0)
w('| outcome | PRs |\n|---|---|\n')
w('| merged clean | **%d** |\n' % n_clean)
w('| conflicted and resolved | **%d** |\n' % n_conf)
w('| already contained in the tree | **%d** |\n' % tally.get('ALREADY', 0))
w('| could not be merged (rival implementation) | **%d** |\n'
  % tally.get('INCOMPATIBLE-NOT-MERGED', 0))
w('| red on its own branch, not a merge issue | **%d** |\n'
  % tally.get('SINGLE-PR-RED', 0))
w('\n')
w('`just test-unit` went **22 failures on `main` -> 63 on the merged tree**\n')
w('(2,004 tests). Of those 63, **37 are the known native-runtime shell-out gap**\n')
w('(docker/bash recipes, #223) and 26 are real. `just test-load` equivalent on the\n')
w('merged tree: **VERDICT ok, 4/4 bots, 0 desyncs over 480 state-hash checks, 0\n')
w('dropped ticks, 0 ticks over D-020\'s budget**, and all three `gate-check.sh`\n')
w('comparisons green.\n\n')
w('**One number to look at: the merged tree fielded 11 squads where the same run\n')
w('on single-PR trees fielded 32-34**, at 448.28 us/squad against ~160-213 at\n')
w('32-34 squads. Per-squad cost is quoted with its squad count as always, and a\n')
w('low count inflates it — but 11 squads is itself the signal. Farms, techs, civ\n')
w('knobs and the new levy costs all change the economy, and stacked they change\n')
w('it a lot. Nothing failed; the match is simply a different match.\n\n')

w('## Five real incompatibilities, all filed\n\n')
w('These are the point of the exercise: **every one of them is invisible on the\n')
w('individual PRs**, and four of the five produce no git conflict at all.\n\n')
w('| issue | what | how it shows up |\n|---|---|---|\n')
w('| **#359** | #237 adds a rule that every artifact writer goes through '
  '`ArtifactPath`; #234 adds a writer that does not | no textual conflict; one '
  'test goes red only in the union |\n')
w('| **#360** | #243 and #324 both fix #309 and **disagree**: `emberdeep_heavy` '
  'gets `shield_wall` from one and `testudo` from the other | git conflicts on '
  'the one contradictory line and is silent about the other five grants |\n')
w('| **#361** | the balance cluster is individually green and collectively red — '
  '9 failures, **D-067\'s shipped siege rule broken** (two spearmen squads leave '
  'a town centre on 360 HP) | seven of the nine PRs merge cleanly |\n')
w('| **#362** | **four** PRs claim wire opcode 39 and **two** claim 40 | #213 '
  'ships the guard that catches it, and #213 is behind three of them in the order |\n')
w('| **#363** | #302 and #246 both claim keyboard `J` (`garrison_wall` vs `farm`) '
  '| `client.gd` does not parse |\n')
w('\n')
w('Two of those (#362, #363) are the same shape: **a scarce namespace allocated by '
  '"next free value on `main`"**. Neither has a guard that can see across branches, '
  'and both produce a collision that exists only in the union.\n\n')

w('## Corrections to the plan above\n\n')
w('The rehearsal disproved two things this document asserted.\n\n')
w('- **Section 1.1 overstated the #340 problem.** Naval stages 1, 3 and 4 are\n')
w('  *genuine ancestors* of #340 — it legitimately builds on the naval chain\n')
w('  rather than duplicating it. Merged in the published order, **#340 costs two\n')
w('  trivial conflicts** (`docs/status/naval.md`, `justfile`). The "41 of 62\n')
w('  files" figure was an artefact of `gh pr view --json files` reporting the\n')
w('  diff against #340\'s *base* (the perf-chain tip), which necessarily includes\n')
w('  every naval file not in that chain. Only **stage 2 (#343) is not an\n')
w('  ancestor**, and that is where the real duplication is.\n')
w('- **#314 and #327 are already fully contained** in the naval chain — both\n')
w('  reported "nothing to merge". They are redundant PRs, which is the *stronger*\n')
w('  form of section 1.2\'s claim.\n')
w('- **The real rival implementation is #308, not #340.** #308 brings its own\n')
w('  water domain against #343\'s: 13 conflict hunks in `squad_sim.gd`, 4 in\n')
w('  `terrain_knowledge.gd`, and the divergent copy of\n')
w('  `D-20260828-water-is-a-second-movement-domain.md`. The rehearsal **aborted**\n')
w('  that merge rather than fabricate a resolution — the correct outcome is that\n')
w('  #308 and #343 must not both land.\n')
w('- **A chain is not always linear.** #243 has four children (#273, #294, #335,\n')
w('  #345) which are SIBLINGS, and siblings conflict with each other exactly like\n')
w('  independent stacks — the first conflict of the whole rehearsal was between\n')
w('  two of them.\n\n')

w('## What "keep both" cannot do\n\n')
w('The rehearsal resolved mechanically wherever it could and recorded the policy\n')
w('per PR. Five places where a mechanical resolution **compiles to nonsense**, all\n')
w('worth knowing before hand-merging:\n\n')
w('- **`bench_render.gd`** — no mechanical merge compiles at all. The my-edotmw-83\n')
w('  and my-edotmw-87 chains both restructure it, renaming variables and changing\n')
w('  `_detail_for()`\'s signature. The rehearsal took the 87 chain\'s file wholesale\n')
w('  and **lost #341\'s host-budget bench work**.\n')
w('- **Format strings.** The load-test `VERDICT` line and the AI\'s `AI_STATS` line\n')
w('  are each one string plus one argument array, extended by **four and three**\n')
w('  different PRs. Every pair conflicts and the tails must be merged by hand.\n')
w('- **Dictionaries.** `BUILD_KEYS` and the `SQUAD_INFO` decoder literal both gain\n')
w('  duplicate keys under keep-both — and in the decoder\'s case the bytes would\n')
w('  also be read in the wrong ORDER, which desynchronises every field after it.\n')
w('- **`just` recipes.** Keep-both produced two `test-client` recipes, and\n')
w('  interleaved `gen-seam-shot` and `gen-naval-shot` into one broken body. Two\n')
w('  recipes also diverged in their **positional signature** (`bench-render` gained\n')
w('  `HOST/PRESET/HULLS` on one side and `ARGS` on the other), which\n')
w('  D-20260817 says silently re-points every existing invocation.\n')
w('- **Refactors that delete a feature\'s home.** Three times a PR moved code that\n')
w('  another PR\'s feature lived inside, so the merge is clean-looking and the\n')
w('  feature is gone: #239 and then #264 each deleted the site where #232 assigns\n')
w('  `_server_endpoint`, so the connection-lost screen (#162) would name an empty\n')
w('  server and **nothing would fail**.\n\n')

w('## Rulings\n\n')
w('Decisions taken by the orchestrator on conflicts this rehearsal surfaced.\n')
w('They override the per-PR table below.\n\n')
w('### #243 vs #324 — the formation grants (#309, issue #360)\n\n')
w('**ARBITRATED 2026-08-28 (orchestrator): #324 keeps the grants and\n')
w("#243's four are superseded.** A make-main-green PR should not carry design;\n")
w('the dedicated PR with the decision entry and the art-tied per-unit\n')
w('reasoning does. Both authors agreed the verdict; the arbitration settled\n')
w('the implementation.\n\n')
w('Implemented as a MERGE-ORDER resolution — **#243\'s branch is not\n')
w('touched** — and **#324 moves to Wave 1, immediately after #243**, so the\n')
w('undecided union does not sit in `main` between them.\n\n')
w('**The resolution is TWO EXPLICIT DELETIONS plus one expected conflict —\n')
w('not "resolve the conflict #324\'s way".** That phrasing reaches one file of\n')
w('three: git conflicts only where both PRs touch the same line, and two of\n')
w("#243's four grants are in files #324 never opens, so they would survive\n")
w('silently and the merged result would be the UNION of five granted units\n')
w('rather than the considered three. `assert_gt(grants, 0)` passes at both,\n')
w('so green cannot tell them apart. (#243\'s author caught this; it is the\n')
w('declared-and-unread shape one level up.)\n\n')
w('| unit | #324 | #243 | conflicts? |\n|---|---|---|---|\n')
w('| `emberdeep_heavy` | `testudo` | `shield_wall` | **yes** → take #324 |\n')
w('| `gildedreach_spearmen` | `shield_wall` | `shield_wall` | no (identical) |\n')
w('| `emberdeep_levy` | `shield_wall` | — | no |\n')
w('| `gravesworn_spearmen` | — | `shield_wall` | no → **delete** |\n')
w('| `stoneblood_heavy` | — | `testudo` | no → **delete** |\n\n')
w("**So the resolution is three actions, not one: take #324's side on\n")
w('`emberdeep_heavy`, AND delete the `formations` line from\n')
w('`gravesworn_spearmen` and from `stoneblood_heavy`.** Those two are not a\n')
w('conflict and git will not offer them — whoever merges #324 removes them\n')
w('deliberately. "Take #324\'s side" alone leaves the union of five standing.\n\n')
w('Verified end to end on a scratch merge: with those two removed, merging\n')
w('#324 conflicts on `emberdeep_heavy` alone and the final granted set is\n')
w("exactly #324's three. `main` is green across the pair — #243 carries\n")
w('grants at its own merge point either way, so there is no red window.\n\n')
w('Worth knowing after it lands: the guard counts **`shield_wall` grantees\n')
w('only**, and there is no `testudo` grantee guard at all — testudo ends with\n')
w('exactly one grantee in the roster and nothing would notice if it lost it.\n\n')
w('### #308 vs #343 — naval stage 2\n\n')
w('**#343 wins. #308 merges DESIGN ONLY.** #308 (worker 80, now inactive)\n')
w("carries a second stage-2 water-domain implementation against #343's, which\n")
w('the rest of the naval chain is built on, including an add/add on a\n')
w('`decisions/` path. Ruled 2026-08-28; worker 88 is commenting it on #308.\n\n')
w('**Delete on merge** — the four the ruling names:\n\n')
w('- `squad_sim.gd` (collides with 5 naval branches)\n')
w("- `terrain_knowledge.gd` (no filename collision, but it is #308's water\n")
w('  plumbing and has no caller once the rest goes)\n')
w('- `tests/test_water_domain.gd` + `.uid` (same — it tests deleted code)\n')
w('- `decisions/D-20260828-water-is-a-second-movement-domain.md` (add/add\n')
w("  against #343; #343's and #340's copies are byte-identical at 9,039 bytes\n")
w("  and #308's is a different 9,436-byte document)\n\n")
w('**And two more the ruling does not name, confirmed colliding here:**\n\n')
w('- `unit_def.gd` — #308 adds its own naval fields, and so do\n')
w('  naval-2/3/4/6/7. Left in, it is a second rival implementation one layer\n')
w('  down from the one being removed.\n')
w("- #308's naval entry in `decisions/D-010.md` — the schema log for the\n")
w('  fields above, which should go with them. The rest of that file is an\n')
w('  ordinary additive conflict (5 naval branches append to it); keep both.\n\n')
w('**Survives, beyond `docs/plans/naval.md`:** `docs/status/naval-plan.md` and\n')
w('its `CLAUDE.md` import line, plus three design entries that collide with\n')
w('nothing — `a-carried-squad-is-cargo`, `a-dock-stands-on-a-shore` and\n')
w('`a-map-a-player-can-pick-is-a-map-an-army-can-cross`.\n\n')
w('**One thing to check when merging, not a ruling:** two of those surviving\n')
w('entries describe subjects the chain IMPLEMENTS — cargo is #333 and docks\n')
w('are #323. They do not collide by filename, so nothing will report it if\n')
w("#308's design and #343's code disagree. That is the D-058/D-065 family:\n")
w('a decision entry that describes code which is not there. Read them against\n')
w('what shipped before merging them.\n\n')
w('### #222 vs #257 — the building HP\n\n')
w('**Expected, and the only conflict inside the balance cluster.** #222 sets\n')
w('`town_centre` 2400 and `tower` 1250; #257 re-derives them to 1900 and 980\n')
w('because #266 and #218 together move a squad\'s break point from ~85%\n')
w('casualties to ~52%, which invalidates the numbers D-067 was measured\n')
w('against (#361). **Take #257\'s values.** Both files, one line each.\n\n')
w('The cluster is otherwise CLEAN from `main` in the published order — every\n')
w('conflict in the rehearsal came from #243 and waves 1-2, not from inside\n')
w('it.\n\n')
w('## Per-PR result\n\n')
w('| PR | branch | result | notes |\n|---|---|---|---|\n')
for pr in order:
    head, status, note = best[pr]
    if pr == '-':
        continue
    w('| #%s | `%s` | %s | %s |\n' % (pr, head, status, note.replace('|', '/')))
w('\n')
for pr in order:
    if pr == '-':
        head, status, note = best[pr]
        w('**%s (%s):** %s\n\n' % (head, status, note))

io.open('docs/plans/merge-order-rehearsal.md', 'w', encoding='utf-8',
        newline='\n').write(o.getvalue())
print('written: %d bytes, %d PRs' % (len(o.getvalue()), len(best)))
print(dict(tally))
