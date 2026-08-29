**`git status` is clean after a Godot recipe, and was not for six
milestones (D-20260818-every-file-has-a-line-ending-rule, #118).**
`.gitattributes` named five patterns; everything else — `.import`,
`.gd`, `.tres`, `.tscn`, `.uid`, `.md` — resolved to `text: unspecified`
and fell through to the machine's `core.autocrlf=true`. **782 of 938
tracked files were checked out CRLF while the index held LF**, and
Godot's importer rewrites the ones it owns with LF, so the working tree
differed from what checkout produced. Git reports that as modified with
`git diff` showing nothing: one `just test-unit` left **136 files
modified, 135 with a zero-line diff**. `git rebase` then refuses to
start with nothing changed.

The fix is one line, written FIRST in the file because gitattributes is
last-match-wins and putting it last would take `binary` off every `.glb`:

```
* text=auto eol=lf
```

**If your worktree already exists, run the settle once.** New clones are
clean by construction; a checkout that predates the fix still holds CRLF
on disk, and `git checkout -- .` will not fix it — git does not re-smudge
a file it considers clean. From the worktree root, on a committed tree:

```
git rm --cached -r -q . && git reset --hard
```

Local only: no commit, no blob change, nothing another branch can
conflict with. Until you run it the symptom is confined to that one
worktree and self-heals per file — `git checkout -- <file>` on anything
that has gone phantom-modified rewrites it LF and it stays clean.

Two things worth carrying:

- **"Unspecified" is not neutral, it is "ask the machine".** The five
  rules that existed were each bought with an incident and each read as
  sufficient; the defect was the ~940 files nobody had an opinion about.
  Same family as the declared-and-unread bugs this project keeps
  finding — nothing failed, and a rule was quietly absent.
- **No renormalisation commit was needed, and that was measured rather
  than assumed.** `git add --renormalize .` over all 941 tracked files,
  with the new attributes in force, stages zero changes: the index was
  already 100% LF. A bulk commit would have touched every file in the
  repo and conflicted with every branch open at the time, for nothing.

---

**And the imported docs are checked for the names they use
(`D-20260828-an-imported-doc-names-the-code-it-is-about`, #291,
2026-08-28).** `CLAUDE.md` `@`-imports all 31 files under `docs/status/`
— 3,372 lines — which makes them **instruction-grade**: handed to every
worker before they read a line of code. `tests/test_status_docs.gd` now
fails if any cited decision id, backticked file path or backticked
`Class.member` in that set does not exist, with one allowlist whose
entries carry their reasons and which fails if an allowlisted name comes
back.

**The defect it was filed for turned out to be the opposite of the one
reported**, and that is the part worth carrying. The gap assessment cited
a status doc paraphrasing D-107 as *"it retries against a different site
now"* and called it false. It is TRUE — `bot_client.gd._found_town_hall`
sites its retry at `offsets[_build_attempts % offsets.size()]` and always
has. What the sentence never said is **which of the two actors it meant**,
and two readers in a row supplied the wrong one: #217's filer used it as
evidence about `ai_player.gd`, and the gap assessment repeated the claim
without re-checking. So the defect is **missing attribution, not
falsehood** — which is why the convention is "a behavioural claim names
the file it is about" rather than anything about truth.

Three mechanisms were measured and rejected, and the numbers are in the
decision so nobody re-derives them: **generating** the docs (they carry
measurements, caveats and rejected alternatives that exist in no source
file); **stamping every claim with a test** (168 headline claims, 13 name
a test — 155 retrofits, most on history that has no guard to name, and a
false stamp is worse than none); and **verifying quoted attributions
verbatim** (42 quoted spans near a decision citation, 25 not found —
almost all because the docs quote playtest reports and code comments far
more than they quote decisions, and nothing marks which is which).

**What it guards is references, not truth**, and the test's own header
says so. A scan cannot read English; it can insist that everything
English names exists.
