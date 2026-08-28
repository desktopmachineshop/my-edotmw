#!/usr/bin/env python3
"""Collect every decision entry that exists only in an open PR (#364).

The decision record is what this project runs on — CLAUDE.md's first
instruction is to read `decisions/` before making an architectural call —
and after one cycle it was **70 entries behind `main`**, because every
entry ships in the PR that carries its code. Gap I4 of
`docs/plans/gap-assessment-2.md` is what that costs: two workers were
told to share a design, could not see each other, and built it twice.

Landing the entries ahead of their code is safe for a reason that is a
property of the repo rather than a hope. `decisions/README.md` rule 1:

    One decision, one file. A new decision is a NEW file in this
    directory. Never append to a shared file — two branches adding
    decisions must be unable to conflict textually.

So a new entry copied to `main` is an add/add of IDENTICAL content when
its own PR lands, which git resolves silently. That property is why this
script copies bytes and never edits them: a single reformat, a single
added "not yet shipped" banner, would turn all 70 silent adds into 70
conflicts and make this change worse than doing nothing.

Run it again rather than trusting it — the same rule
`docs/plans/merge-order.gen.py` (#350) states. Its inputs are stale the
moment anything merges.

    python docs/plans/decisions-ahead.gen.py --write

Without --write it reports and changes nothing.
"""

import argparse
import collections
import io
import json
import os
import subprocess
import sys

MAIN = "origin/main"
DECISIONS = "decisions"
MANIFEST = "docs/plans/decision-manifest.md"

# The schema log is the ONE decision file this project appends to rather
# than adding beside, and #366 exists to split it. Until it is split it
# has to be merged by hand, so it is handled separately and reported
# loudly — never folded in with the conflict-free entries.
# Everything about the schema log belongs to #368 (which does #366: split
# it into one file per workstream), and it belongs there WHOLE.
#
# #364 was written asking for "every decision entry + the schema-log
# append", and at the time that was right — six PRs were appending to one
# monolith and somebody had to union them. #368 opened while this branch
# was being built and does the structural fix instead: `D-010.md` becomes
# an index and the entries move to `D-010-schema-{units,buildings,civs,
# techs,naval,audio}.md`.
#
# So this branch does NOT union the appends. Unioning a file that is
# about to be split is work that is thrown away and conflicts with the
# fix; and landing #368's six new files without its restructured index
# would leave six entries nothing points to, with D-010 still a monolith.
# A restructure is atomic, and half-applying somebody else's is worse
# than not applying it.
#
# The six pending appends are listed in the manifest instead, with the
# per-workstream file each belongs in once #368 lands.
SCHEMA_PREFIX = "decisions/D-010"

# The six independent appends to the schema log, newest chain first.
# Keyed by BLOB rather than branch, because several branches share a blob
# and the pairing of blob to author is what the manifest has to report.
SCHEMA_VARIANTS = [
    ("df75cbc3", "naval chain — #333 #340 #342 #343 #352 #353"),
    ("0fba3891", "#314 naval content"),
    ("edc7333a", "#323 naval docks"),
    ("339df7ab", "#308 naval design"),
    ("0a31011d", "#246 the farm, #312 renewable metals"),
    ("6593370f", "#336 four more civ knobs"),
]


def git(*args):
    out = subprocess.run(["git"] + list(args), capture_output=True, text=True)
    if out.returncode != 0:
        raise SystemExit("git %s failed: %s" % (" ".join(args), out.stderr.strip()))
    return out.stdout


def blob(sha):
    return subprocess.run(["git", "cat-file", "-p", sha],
                          capture_output=True).stdout


def open_prs():
    """(number, head branch, title) for every open PR, from gh."""
    out = subprocess.run(
        ["gh", "pr", "list", "--state", "open", "--limit", "200", "--json",
         "number,headRefName,title"], capture_output=True)
    if out.returncode != 0:
        raise SystemExit("gh pr list failed")
    # Decoded EXPLICITLY. `text=True` uses the locale encoding, which on
    # Windows is cp1252 — and the first version of this script did use
    # it, so every em dash in a PR title reached the manifest as
    # mojibake. #214 is the same defect in the shipped civ summaries;
    # this one was reintroduced by a tool, in a file whose own docstring
    # warns about it, which is worth leaving written down.
    return [(str(p["number"]), p["headRefName"], p["title"])
            for p in json.loads(out.stdout.decode("utf-8"))]


def declared_bases():
    """{pr number: base branch} from GitHub, for the stack graph."""
    out = subprocess.run(
        ["gh", "pr", "list", "--state", "open", "--limit", "200", "--json",
         "number,baseRefName"], capture_output=True)
    if out.returncode != 0:
        return {}
    return {str(p["number"]): p["baseRefName"]
            for p in json.loads(out.stdout.decode("utf-8"))}


def tree(ref, path):
    """{path: blob sha} for the .md files under `path` at `ref`."""
    found = {}
    listing = subprocess.run(["git", "ls-tree", "-r", ref, path + "/"],
                             capture_output=True, text=True)
    if listing.returncode != 0:
        return found
    for line in listing.stdout.strip().split("\n"):
        if not line:
            continue
        meta, name = line.split("\t", 1)
        sha = meta.split()[2]
        if name.endswith(".md"):
            found[name] = sha
    return found


def descends_from(child, ancestor):
    """True when `child` has `ancestor` in its history."""
    return subprocess.run(
        ["git", "merge-base", "--is-ancestor", ancestor, child],
        capture_output=True).returncode == 0


def downstream_by_declared_base(a_prs, b_prs, base_of, head_of):
    """True when some PR in `a_prs` is downstream of one in `b_prs`.

    Uses GitHub's declared `baseRefName` edges — the same graph #350's
    merge order is built from — rather than commit ancestry, because a
    stacked branch that has been rebased no longer literally descends
    from its parent's tip while still being its continuation. #296 is
    exactly that: its base IS #225's head branch, its copy of the entry
    is #225's plus an "Amended" block, and `git merge-base` says they
    are unrelated.
    """
    for a in a_prs:
        seen, cursor = set(), a
        while cursor in base_of and base_of[cursor] != "main":
            parent = head_of.get(base_of[cursor])
            if parent is None or parent in seen:
                break
            if parent in b_prs:
                return True
            seen.add(parent)
            cursor = parent
    return False


def resolve(path, variants, branch_of, base_of=None, head_of=None):
    """Pick the one version of `path` to copy, or None to skip it.

    `variants` is {blob: [pr numbers]}. One blob is the ordinary case.

    Several blobs means two branches carry the same decision file with
    different bytes, and there are exactly two reasons for that. Either
    one branch is DOWNSTREAM of the other and amended the entry, in which
    case the descendant is the current version and the choice is
    mechanical; or the two are unrelated, in which case two authors wrote
    different things and a script has no business deciding. The second is
    reported and skipped, because a wrong entry landed early is worse
    than a missing one — a reader can see that something is absent.
    """
    if len(variants) == 1:
        return next(iter(variants.items()))

    tips = {}
    for sha, prs in variants.items():
        for pr in prs:
            tips.setdefault(sha, []).append("origin/" + branch_of[pr])

    winner = None
    for sha, refs in tips.items():
        others = [r for other, rs in tips.items() if other != sha for r in rs]
        if all(any(descends_from(mine, theirs) for mine in refs)
               for theirs in others):
            winner = sha
            break

    # Second rule: the declared PR graph, for a stack that has been
    # rebased out of literal commit ancestry.
    if winner is None and base_of is not None:
        for sha, prs in variants.items():
            rest = [p for other, ps in variants.items() if other != sha for p in ps]
            if rest and downstream_by_declared_base(prs, set(rest), base_of, head_of):
                winner = sha
                break

    if winner is None:
        return None
    return winner, variants[winner]


def schema_log_entries(lines):
    """[(headline, [rest])] for each `- **` block of the schema log."""
    out, current = [], None
    for line in lines:
        if line.startswith("- **"):
            current = (line, [])
            out.append(current)
        elif current is not None:
            current[1].append(line)
    return out


def text_of(ref_or_sha):
    """UTF-8 lines, decoded explicitly.

    Never `text=True`: on Windows that decodes as cp1252 and turns every
    em dash in the log into a replacement character — #214's defect,
    reintroduced by a tool instead of by data.
    """
    if ":" in ref_or_sha:
        raw = subprocess.run(["git", "show", ref_or_sha], capture_output=True).stdout
    else:
        raw = subprocess.run(["git", "cat-file", "-p", ref_or_sha],
                             capture_output=True).stdout
    return raw.decode("utf-8").split("\n")


def merge_schema_log(variants, write):
    """Union the independent appends to the ONE decision file that is a
    monolith (#366 exists to split it).

    Every variant is asserted to be a PURE APPEND relative to `main`
    first — an entry that also *edited* existing text is a real
    disagreement and this must not paper over it. Entries are keyed by
    their headline, so an entry already on `main` is never duplicated.
    """
    main_lines = text_of(MAIN + ":" + SCHEMA_LOG)
    already = {head for head, _ in schema_log_entries(main_lines)}
    on_main_set = set(main_lines)

    merged, source_of = [], {}
    for sha, who in variants:
        lines = text_of(sha)
        removed = [l for l in main_lines if l not in set(lines)]
        if removed:
            print("  REFUSING %s (%s): it EDITS the log, it does not append" % (sha[:10], who))
            continue
        for head, rest in schema_log_entries(lines):
            if head in already:
                continue
            already.add(head)
            while rest and rest[-1].strip() == "":
                rest.pop()
            merged.append((head, rest))
            source_of[head] = who

    cut = max(i for i, l in enumerate(main_lines) if l.strip() == "---")
    body = list(main_lines[:cut])
    while body and body[-1].strip() == "":
        body.pop()
    for head, rest in merged:
        body.append("")
        body.append(head)
        body.extend(rest)
    body.append("")
    body.extend(main_lines[cut:])

    if write:
        with io.open(SCHEMA_LOG, "w", encoding="utf-8", newline="\n") as handle:
            handle.write("\n".join(body))
    print("schema log: %d new entries (%d -> %d lines)"
          % (len(merged), len(main_lines), len(body)))
    return [(head, source_of[head]) for head, _ in merged]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--write", action="store_true",
                        help="write the entries and the manifest")
    args = parser.parse_args()

    prs = open_prs()
    branch_of = {n: b for n, b, _ in prs}
    title_of = {n: t for n, _, t in prs}
    head_of = {b: n for n, b, _ in prs}
    base_of = declared_bases()
    on_main = tree(MAIN, DECISIONS)

    # path -> {blob: [pr, ...]}
    seen = collections.defaultdict(lambda: collections.defaultdict(list))
    for number, branch, _ in prs:
        for path, sha in tree("origin/" + branch, DECISIONS).items():
            seen[path][sha].append(number)

    new, amended, schema_held = {}, {}, {}
    for path, variants in seen.items():
        if path.startswith(SCHEMA_PREFIX):
            schema_held[path] = variants
            continue
        if path not in on_main:
            new[path] = variants
        elif any(sha != on_main[path] for sha in variants):
            amended[path] = variants

    copied, ambiguous = {}, {}
    for path in sorted(new):
        chosen = resolve(path, dict(new[path]), branch_of, base_of, head_of)
        if chosen is None:
            ambiguous[path] = new[path]
            continue
        sha, prs_with_it = chosen
        copied[path] = (sha, sorted(set(prs_with_it), key=int))

    print("decision entries on %s:        %d" % (MAIN, len(on_main)))
    print("paths across %d open PRs:      %d" % (len(prs), len(seen)))
    print("new, not on main:              %d" % len(new))
    print("  copyable:                    %d" % len(copied))
    print("  ambiguous (two authors):     %d" % len(ambiguous))
    print("amended in place (excluded):   %d" % len(amended))
    print("schema log, held for #368:     %d" % len(schema_held))

    for path, variants in sorted(ambiguous.items()):
        print("  AMBIGUOUS %s" % path)
        for sha, prs_with_it in variants.items():
            print("      %s  PRs %s" % (sha[:10],
                                        ", ".join("#" + p for p in sorted(set(prs_with_it), key=int))))

    if not args.write:
        return

    for path, (sha, _) in copied.items():
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "wb") as handle:
            handle.write(blob(sha))
    print("wrote %d entries" % len(copied))

    write_manifest(copied, ambiguous, amended, title_of, base_of, len(on_main))


def introducer(path, prs, base_of):
    """The PR that ADDS `path` — the one whose base does not have it.

    The first version took the lowest PR number, which is right by
    coincidence for a stack whose root was opened first and wrong for
    anything else. The manifest's whole job is to say which PR an entry's
    code is in, so it has to be the PR that introduces it rather than the
    earliest one that happens to carry it.
    """
    for pr in sorted(prs, key=int):
        base = base_of.get(pr)
        if base is None:
            continue
        if base == "main" or path not in tree("origin/" + base, DECISIONS):
            return pr
    return None



def write_manifest(copied, ambiguous, amended, title_of, base_of, on_main,
                   schema=None):
    lines = []
    add = lines.append
    add("# Decision manifest — which PR each entry's code is waiting in")
    add("")
    add("**Generated** by `docs/plans/decisions-ahead.gen.py` (#364), from")
    add("`origin/main` and the open PR queue. **Re-run it rather than trusting")
    add("it** — every row below is stale the moment a PR merges.")
    add("")
    add("`decisions/` on `main` held **%d** entries before this branch; it holds"
        % on_main)
    add("**%d** after. The %d added ones describe code that is **not on `main`**"
        % (on_main + len(copied), len(copied)))
    add("yet. This table is the only thing that says so, which is why it exists:")
    add("read an entry, then check here before assuming its code is in the game.")
    add("")
    add("| entry | code waits in | PR title |")
    add("|---|---|---|")
    for path, (_, prs) in sorted(copied.items()):
        owner = introducer(path, prs, base_of) or prs[0]
        rest = [p for p in prs if p != owner]
        others = ("".join(" #" + p for p in rest[:5])
                  + (" (+%d)" % (len(rest) - 5) if len(rest) > 5 else ""))
        add("| `%s` | **#%s**%s | %s |"
            % (os.path.basename(path), owner, others,
               title_of.get(owner, "").replace("|", "\|")[:70]))
    add("")

    if ambiguous:
        add("## Deliberately NOT landed — two authors, different bytes")
        add("")
        add("These entries exist on several branches with **different content**,")
        add("and the branches are not related by history — so this is two people")
        add("writing different things under one ID, not an amendment. A script")
        add("must not pick. **A missing entry is visible; a wrong one is not.**")
        add("")
        for path, variants in sorted(ambiguous.items()):
            add("- `%s`" % os.path.basename(path))
            for sha, prs in variants.items():
                add("  - `%s` in %s" % (sha[:10],
                                        ", ".join("#" + p for p in sorted(set(prs), key=int))))
        add("")

    if amended:
        add("## Deliberately NOT landed — amendments to entries already on `main`")
        add("")
        add("An amendment edits a file `main` already has, so landing it early")
        add("turns a silent add/add into a real conflict on every PR that")
        add("carries it. That is the opposite of this branch's whole premise.")
        add("")
        for path, variants in sorted(amended.items()):
            prs = sorted({p for v in variants.values() for p in v}, key=int)
            add("- `%s` — amended by %s"
                % (path, ", ".join("#" + p for p in prs)))
        add("")

    if schema:
        add("## The schema log — the one file that WILL conflict")
        add("")
        add("`%s` is the only decision file this project appends to rather" % SCHEMA_LOG)
        add("than adding beside, and **six open PRs append to it independently**.")
        add("That is the monolith `decisions/README.md` rule 1 forbids, and **#366**")
        add("exists to split it. Until it is, the appends are unioned here by hand.")
        add("")
        add("**This file, and only this file, will conflict when those PRs merge.**")
        add("The resolution is always the same and is never a judgement: the entry")
        add("is *already on `main`*, so take `main`'s side and keep the rest of the")
        add("PR's diff. Every variant was asserted to be a pure APPEND before it was")
        add("merged in, so no PR's text is discarded by that resolution.")
        add("")
        add("| schema entry | appended by |")
        add("|---|---|")
        for head, who in schema:
            add("| %s | %s |" % (head.lstrip("- ").strip()[:96].replace("|", "\|"), who))
        add("")
        add("**#367 came out of this union.** `UnitDef.movement_domain` is logged")
        add("twice with different defaults — `\"ground\"` by two implementing chains")
        add("and `\"land\"` by #308, the design PR. Two chains defined one field")
        add("without seeing each other, and putting the log in one place is what")
        add("made it visible. The entries are copied verbatim here; #367 is where")
        add("it gets settled.")
        add("")
    add("## The schema log is #368's, whole")
    add("")
    add("`decisions/D-010.md` and every `D-010-schema-*.md` is **held back**")
    add("deliberately. #364 was written asking for the schema-log append too,")
    add("and at the time that was right: six PRs were appending to one monolith")
    add("and somebody had to union them. **#368 opened while this branch was")
    add("being built** and does the structural fix instead (#366) — `D-010.md`")
    add("becomes an index and the entries move to")
    add("`D-010-schema-{units,buildings,civs,techs,naval,audio}.md`.")
    add("")
    add("Unioning a file that is about to be split is work thrown away that also")
    add("conflicts with the fix. And landing #368's six new files *without* its")
    add("restructured index would leave six entries nothing points to, with")
    add("`D-010.md` still a monolith. **A restructure is atomic, and")
    add("half-applying somebody else's is worse than not applying it.**")
    add("")
    add("The six appends waiting on it: #308 and the #314/#323/#333 naval")
    add("chain, #246 and #312 (the farm and renewable metals), #336 (four more")
    add("civ knobs).")
    add("")
    add("**#367 came out of looking at them together.** `UnitDef.movement_domain`")
    add("is logged twice with different defaults — `ground` by two implementing")
    add("chains and `land` by #308, the design PR — because two chains defined")
    add("one field without seeing each other. Putting the log in one place is")
    add("what made it visible, which is this branch's whole argument in one")
    add("field name.")
    add("")

    with open(MANIFEST, "w", encoding="utf-8", newline="\n") as handle:
        handle.write("\n".join(lines) + "\n")
    print("wrote %s" % MANIFEST)


if __name__ == "__main__":
    sys.exit(main())
