# -*- coding: utf-8 -*-
"""Regenerates docs/plans/merge-order.md from the GitHub PR graph.

Run from the repository root. It needs three snapshot files beside it, none of
which are committed because they go stale the moment a PR merges:

  gh pr list --repo <repo> --state open --limit 200      --json number,title,headRefName,baseRefName,mergeable > prs.json

  # prfiles.json: {"<pr>": [changed paths]} for every PR in prs.json
  for n in $(...); do gh pr view $n --json files -q '[.files[].path]'; done

  # graph.json: {"parent": {"<pr>": <base pr or null>}}, derived by matching each
  # PR's baseRefName against every other PR's headRefName.
"""
import json, collections, io, itertools

L = lambda p: json.load(io.open(p, encoding='utf-8'))
prs = {p['number']: p for p in L('prs.json')}
files = {int(k): set(v) for k, v in L('prfiles.json').items()}
parent = {int(k): v for k, v in L('graph.json')['parent'].items()}

children = collections.defaultdict(list)
for n in prs:
    if parent.get(n) is not None:
        children[parent[n]].append(n)


def root(n):
    while parent.get(n) is not None:
        n = parent[n]
    return n


R = {n: root(n) for n in prs}
byhead = {p['headRefName']: k for k, p in prs.items()}


def risky(f):
    return not (f.startswith('decisions/D-') or f.startswith('docs/playtest/')
                or f.startswith('docs/art-reference/'))


HOT = {'server.gd', 'client.gd', 'squad_sim.gd', 'combat.gd', 'building_sim.gd',
       'net_protocol.gd', 'client_state.gd', 'unit_def.gd', 'match_state.gd',
       'bot_build_plan.gd', 'ai_player.gd', 'civ_def.gd', 'economy.gd',
       'vision.gd', 'formation.gd', 'engagement.gd', 'terrain_gen.gd',
       'justfile', 'CLAUDE.md'}

owners = collections.defaultdict(list)
for n in prs:
    for f in files[n]:
        owners[f].append(n)


def baselabel(n):
    b = prs[n]['baseRefName']
    return ('#%d' % byhead[b]) if b in byhead else 'main'


def title(n):
    return prs[n]['title'].replace('|', '/')


DASH = u'—'
ARROW = u'→'

WAVES = [
    (u"Wave 1 %s make main green" % DASH, [222, 243, 324, 335, 294, 273, 345],
     "Blocking, and strictly in this order: #243 is stacked on #222, and "
     "#273/#294/#335/#345 are all stacked on #243. Nothing else in the queue can "
     "be tested honestly until #243 lands. **#324 is moved here from Wave 3 by "
     "the #360 arbitration** -- it is data plus tests with no dependencies, and "
     "landing it immediately after #243 keeps the undecided union of formation "
     "grants out of `main`. See the Rulings section: its merge is three actions, "
     "not one."),
    (u"Wave 2 %s low-conflict singles" % DASH,
     [265, 238, 226, 232, 235, 237, 234, 251, 248, 255, 322],
     "Independent chains of one, each touching at most one hot file. Merge in any "
     "order; they exist to bank reviews and shrink the queue."),
    (u"Wave 3 %s the balance / civ cluster (my-edotmw-82)" % DASH,
     [221, 252, 260, 261, 321, 330, 334, 347, 328, 257, 297, 336],
     u"Mostly roster `.tres` and tests. #334 must precede #347 (stacked) and #222 "
     u"must already be in (#252 is stacked on it)."),
    (u"Wave 4 %s playtest and assessment docs" % DASH, [233, 293, 299],
     "Documentation-heavy, so merge late enough to describe the merged tree and "
     "early enough not to rot. #299 also carries `squad_sim.gd` and `unit_def.gd`."),
    (u"Wave 5 %s the my-edotmw-83 tech/pacing chain" % DASH, [225, 296, 319, 341],
     "Touches `server.gd`, `client.gd`, `squad_sim.gd`, every `civs/*.tres` and the "
     "`justfile`. Merge as a block, after the balance cluster has settled the "
     "rosters."),
    (u"Wave 6 %s the my-edotmw-87 performance chain" % DASH,
     [250, 263, 272, 274, 298, 307, 310, 317, 326, 329, 331],
     u"Strictly linear and heavy on `client.gd`. **#340 is deliberately excluded** "
     u"%s see section 1.1. Merge up to #331 and stop. #310 re-encodes every "
     u"`civs/*.tres`, so it must come after anything else that edits them." % DASH),
    (u"Wave 7 %s the my-edotmw-79 M8/Steam chain" % DASH,
     [205, 213, 239, 242, 256, 258, 264, 295, 300, 306, 320, 348, 271, 303],
     "The largest chain in the queue at 14 PRs and 144 files, heavy on `server.gd`, "
     "`client.gd` and the `justfile`. #271 branches off #205 and #303 off #258, so "
     "both can land earlier than the tail."),
    (u"Wave 8 %s economy" % DASH, [246, 312],
     "#312 is stacked on #246. Both touch `building_sim.gd` and `server.gd`."),
    (u"Wave 9 %s naval, ONLY after section 1 is resolved" % DASH,
     [216, 313, 323, 333, 343, 342, 327, 314, 308, 340],
     u"Do not start this wave until somebody has decided whether naval ships via "
     u"the #216 chain or via #340, and which of #314/#323/#340 owns the hulls. The "
     u"order shown is the branch graph's, which runs stages 1, 3, 4, 2, 7 %s not "
     u"stage order." % DASH),
]

FIRST_FIVE = [
    (222, "the D-067 re-derivation the whole balance cluster sits behind, and "
          "#243/#252 are stacked on it"),
    (243, "makes `test-unit` green and the docker estate runnable; four PRs are "
          "stacked on it and nothing else can be tested honestly until it lands"),
    (265, u"one file, docs only %s zero conflict surface" % DASH),
    (238, "`justfile` only, no shipped code"),
    (226, "six files, `server.gd` only, self-contained"),
]

o = io.StringIO()
w = o.write

w("# Merge order for the open PR queue\n\n")
w("**Generated 2026-08-28**, from GitHub's own `baseRefName` edges and per-PR\n")
w("changed-file lists for the %d PRs open at that moment. Every table is\n" % len(prs))
w("mechanical; regenerate rather than trust it once PRs start landing.\n\n")
w("**Method.** Chains are built from each PR's actual base branch. A PR based on\n")
w("`main` is a chain ROOT. \"Conflict\" means two PRs on *independent* chains change\n")
w("the same file, so whichever merges second must rebase. New decision entries and\n")
w("playtest images are excluded from the conflict counts because they are new\n")
w(u"files %s except where two chains create the same decision *filename*, which is\n" % DASH)
w("a content collision and is called out separately.\n\n")
w("- %d open PRs, %d chain roots, all reported MERGEABLE by GitHub.\n"
  % (len(prs), len([n for n in prs if parent.get(n) is None])))
w("- Largest chains: **#205 (14 PRs, 144 files)**, **#250 (12 PRs, 112 files)**,\n")
w("  #222 (7), #216 (7), #225 (4). Longest path is **12 deep**:\n")
w(u"  `#205 %(a)s #213 %(a)s #239 %(a)s #242 %(a)s #256 %(a)s #258 %(a)s #264 %(a)s\n"
  % {'a': ARROW})
w(u"  #295 %(a)s #300 %(a)s #306 %(a)s #320 %(a)s #348`. #340 is also 12 deep, on\n"
  % {'a': ARROW})
w("  the #250 chain.\n")
w("- No CI is configured on this repository, so \"green\" means a local\n")
w("  `just test-unit`, not a check on the PR.\n\n")

w(u"## 1. Read this first %s three things no merge ORDER can fix\n\n" % DASH)
w("### 1.1 PR #340 is not stage 8. It is the whole naval stack on the wrong root.\n\n")
w("`#340 ao/my-edotmw-87/naval-8-presentation` is based on the **my-edotmw-87\n")
w("performance chain** (root #250), not on the naval chain. Its diff carries **41\n")
w(u"of the naval chain's 62 files** %s the water graph, the movement domain, docks,\n" % DASH)
w(u"embark and the whole hull roster %s as well as its own presentation work. Its\n" % DASH)
w("copy of `decisions/D-20260828-water-is-a-second-movement-domain.md` is\n")
w("**byte-identical** to #343's (md5 `22bb849a`), which is what confirms it is a\n")
w("rebase of that work rather than an addition on top of it.\n\n")
w("Merging both the naval chain and #340 double-applies naval. **Somebody has to\n")
w("decide which branch carries naval before either is merged**, and no ordering\n")
w("avoids it. This is the largest single item in the queue.\n\n")
w("### 1.2 The hulls and the dock are shipped by three independent chains\n\n")
w("`buildings/dock.tres`, `units/*_warship.tres`, `units/*_transport.tres`,\n")
w("`units/*_warboat.tres`, `tests/test_naval_roster.gd` and the naval fields in\n")
w("`unit_def.gd` are each created by **#314** (its own root, on `main`), **#323**\n")
w("(root #216) and **#340** (root #250). #314 overlaps the naval chain on 17 files\n")
w("and #340 on 17. Two of the three have to be dropped or reduced to a delta.\n\n")
w("### 1.3 One decision id, two different documents\n\n")
w("`decisions/D-20260828-water-is-a-second-movement-domain.md` exists on three\n")
w("branches: #343 and #340 are identical at 9,039 bytes, and **#308's is a\n")
w("different document at 9,436 bytes**. The project's rule is one file per decision\n")
w("and never a renumber, so this needs the authors to reconcile it, not a merge\n")
w("resolution. `D-20260828-the-water-graph-is-the-inverse-of-the-ground.md` is\n")
w("likewise in both #313 and #340.\n\n")

w("## 2. Recommended first five merges\n\n")
w("| # | PR | branch | why this one first |\n|---|---|---|---|\n")
for i, (n, why) in enumerate(FIRST_FIVE, 1):
    w("| %d | #%d | `%s` | %s |\n" % (i, n, prs[n]['headRefName'], why))
w("\n#222 then #243 is both the orchestrator's directive and what the graph\n")
w("requires.\n\n")

w("## 3. Merge order\n\n")
w(u"Within a chain the order is forced %s parent before child. Between chains, the\n" % DASH)
w("order below puts the chain that OWNS a contended file ahead of the chains that\n")
w("merely touch it, so the later ones rebase onto a settled version.\n\n")
placed = set()
for name, members, note in WAVES:
    w("### %s\n\n%s\n\n" % (name, note))
    w("| order | PR | base | branch | what it is |\n|---|---|---|---|---|\n")
    for i, n in enumerate(members, 1):
        w("| %d | #%d | %s | `%s` | %s |\n"
          % (i, n, baselabel(n), prs[n]['headRefName'], title(n)))
        placed.add(n)
    w("\n")
    inner = []
    for a, b in itertools.combinations(members, 2):
        if R[a] == R[b]:
            continue
        common = sorted(f for f in files[a] & files[b] if risky(f))
        if common:
            inner.append((a, b, common))
    if inner:
        w("Cross-chain file collisions *inside* this wave, so the second of each\n")
        w("pair rebases:\n\n")
        for a, b, common in inner:
            w("- #%d and #%d %s `%s`\n" % (a, b, DASH, "`, `".join(common)))
        w("\n")
assert placed == set(prs), sorted(set(prs) - placed)

w("## 4. Expected conflicts between independent chains\n\n")
w(u"Only files changed by PRs on **different** chains %s inside a chain the parent\n" % DASH)
w("merges first, so those are not conflicts. Sorted by how many independent chains\n")
w("touch the file, which is the number that predicts pain.\n\n")
w("| file | chains | PRs that change it (chain root in brackets) |\n|---|---|---|\n")
rows = []
for f in owners:
    if not risky(f):
        continue
    rts = {R[n] for n in owners[f]}
    if len(rts) >= 2 and (f in HOT or len(rts) >= 3):
        rows.append((len(rts), f, sorted(owners[f])))
for nr, f, ns in sorted(rows, key=lambda x: (-x[0], x[1]))[:34]:
    cell = ", ".join("#%d[%d]" % (n, R[n]) for n in ns)
    if len(cell) > 150:
        cell = cell[:147] + u'…'
    w("| `%s` | %d | %s |\n" % (f, nr, cell))
w("\n")
w("**How to read it.** `server.gd` (14 chains, 20 PRs) and `client.gd` (10 chains,\n")
w("26 PRs) will conflict textually on nearly every merge after the first few. Both\n")
w("are dispatch/`_ready` files where the changes are additive, so those conflicts\n")
w(u"are *mechanical* %s two PRs adding a case to the same match statement. Budget\n" % DASH)
w("for them rather than re-planning around them.\n\n")
w("The ones that are **not** mechanical, and want a named owner:\n\n")
w(u"- **`squad_sim.gd`** %s 7 chains, 13 PRs (#225, #257, #273, #308, #319, #323,\n" % DASH)
w("  #327, #333, #335, #336, #340, #342, #343). #319 *restructures* the tick phases\n")
w("  (separation over-scanning) while #257 adds a morale-suppression read and the\n")
w("  naval PRs add a second movement domain. **Merge #319 before #257 and before\n")
w("  naval**, or those rebase onto a tick loop that has moved under them.\n")
w(u"- **`combat.gd`** %s 4 chains (#257, #327, #328, #335, #342). #257 (no morale\n" % DASH)
w("  recovery under fire) and #328 (morale as a fraction of the squad, not a count\n")
w("  of men) are two edits to the same morale arithmetic from different roots.\n")
w("  **Merge #328 first**: it changes what a casualty COSTS, so #257's constants\n")
w("  are then reviewable against the final numbers instead of the old ones.\n")
w(u"- **`unit_def.gd`** %s 5 chains (#308, #314, #323, #328, #340). #328 adds the\n" % DASH)
w("  morale-scaling function; the other four all add naval fields. These are schema\n")
w("  additions, so `decisions/D-010.md`'s schema log conflicts alongside them.\n")
w(u"- **every `civs/*.tres`** %s 5 chains (#225, #246, #295, #310, #321, #336).\n" % DASH)
w("  #310 re-encodes them as UTF-8 (#236) while the others add fields or change\n")
w("  numbers. **Merge #310 last of that set.** A re-encode of a file somebody else\n")
w("  also edited is the one conflict git resolves badly, because every line reads\n")
w("  as changed.\n")
w(u"- **`bot_build_plan.gd` and its test** %s 4 chains each, and three of them\n" % DASH)
w("  (#314, #323, #340) are the duplicated naval work from section 1.2 rather than\n")
w("  four independent changes.\n\n")

w("## 5. Every open PR\n\n")
w("| PR | chain root | base | branch | what it is |\n|---|---|---|---|---|\n")
for n in sorted(prs):
    w("| #%d | #%d | %s | `%s` | %s |\n"
      % (n, R[n], baselabel(n), prs[n]['headRefName'], title(n)))
w("\n---\n\n")
w("Regenerate with `genplan.py` beside `prs.json`, `prfiles.json` and `graph.json`,\n")
w("which come from `gh pr list --json number,title,headRefName,baseRefName` and\n")
w("`gh pr view <n> --json files`.\n")

io.open('docs/plans/merge-order.md', 'w', encoding='utf-8',
        newline='\n').write(o.getvalue())
print("written: %d bytes, %d PRs, all placed" % (len(o.getvalue()), len(prs)))
