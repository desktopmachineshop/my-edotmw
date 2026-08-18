# D-20260818-every-file-has-a-line-ending-rule · 2026-08-18 · Accepted

**`.gitattributes` answers for EVERY tracked file, not for five patterns.
"Unspecified" is not neutral — it means "ask the machine".**

## Decision

`.gitattributes` gains one catch-all, written FIRST in the file:

```
* text=auto eol=lf
```

Every existing rule stays exactly where it is and still wins, because
gitattributes is last-match-wins. Two additions ride with it, both
naming files the catch-all reaches for the first time:

- `*.ttf binary`, `*.fnt binary` — GUT's bundled fonts. Git's own
  auto-detection already calls them binary, so this changes nothing
  today; it is written down for the same reason `*.glb`/`*.exr`/`*.png`
  are, because a CRLF substitution inside a font corrupts silently.
- `*.ps1 text eol=crlf` — `bootstrap.ps1` is the fresh-clone entry
  point, run by Windows PowerShell before anything else in this repo
  exists. CRLF is the safe side of that bet and LF buys nothing on a
  file nothing but PowerShell reads.

`tests/test_line_endings.gd` re-implements last-match-wins over the
patterns actually written and checks the result against the files
actually on disk, so losing the property FAILS.

**No renormalisation commit is needed, and this was measured rather than
assumed.** The index is already 100% LF: `git add --renormalize .` over
all 941 tracked files, with the new attributes in force, stages **zero**
changes. What is out of date is the WORKING TREE of checkouts that
already exist — see Consequences.

## Rationale

The dev machine has `core.autocrlf=true` (from the system gitconfig, so
every checkout on it inherits it). `.gitattributes` named five patterns
— `*.sh`, `Dockerfile`, `justfile`, `*.py`, and the `*.glb`/`*.exr`/
`*.png` binaries — each bought with a real incident. Everything else
resolved to `text: unspecified`, which falls through to `autocrlf`:

```
$ git check-attr text eol -- generated/models/militia.glb.import
generated/models/militia.glb.import: text: unspecified
generated/models/militia.glb.import: eol: unspecified
```

Measured on this checkout before the change, over the 938 tracked files
git has an opinion about:

| index / worktree | files |
|---|---|
| `i/lf w/crlf` | **782** |
| `i/-text w/-text` (binary) | 134 |
| `i/lf w/lf` (the five rules) | 17 |

So 782 files were checked out CRLF while the index held LF. Godot's
importer then rewrites the ones it owns — `.import`, and in a session
that touches them `.uid`/`.tres`/`.tscn` — with **LF**. The working tree
now differs from what checkout produced, and git reports that as
modified while showing no content diff at all:

```
$ git status --short generated/models/militia.glb.import
 M generated/models/militia.glb.import
$ git diff --numstat generated/models/militia.glb.import
(nothing)
```

Reproduced live in this branch: a single `just test-unit` left **136
files modified, 135 of them with a zero-line diff**. The costs, all real
(#118): `git rebase` refuses to start ("cannot rebase: You have unstaged
changes") with nothing changed, `git add -A` sweeps 138 no-op files into
every commit, and `git status` — the one tool that must stay legible
when a dozen agents work in parallel worktrees — is unreadable.

**The catch-all is FIRST on purpose.** Last-match-wins means a rule
written at the BOTTOM of the file overrides everything above it, so
`* text=auto eol=lf` placed last would silently take `binary` off every
`.glb` in `generated/`. Nothing would fail until a model broke, which is
this project's oldest defect shape. The test pins the ordering by
resolving `*.py` → `eol=lf` and `*.glb` → `-text` rather than by
asserting a line number.

## Rejected alternatives

- **`core.autocrlf=false` on the dev machine.** Fixes that machine and
  nobody else's, and silently un-fixes itself on the next clone or the
  next agent's host. The repo-level attributes are the only durable
  answer, which is why this is a repo-settings decision and not a note
  in a shell profile.
- **A bulk `git add --renormalize` commit.** Measured to change nothing
  (see above), and it would have touched every file in the repo — a
  guaranteed conflict against every branch open at the time. Rejected on
  measurement, not on taste.
- **Naming the Godot-written extensions individually** (`*.import`,
  `*.uid`, `*.tres`, `*.tscn`, `*.gd`, ...). It fixes today's list and
  not tomorrow's; the defect is that a file can go unanswered at all.
- **`eol=native` for the catch-all.** That is what `autocrlf` already
  does, i.e. the bug. The repo's committed form is LF and its containers
  read it as LF, so LF is what a checkout should produce.

## Consequences

- **A fresh clone is clean by construction**, and stays clean across any
  recipe that runs Godot.
- **An EXISTING worktree needs a one-time local settle.** Files already
  on disk as CRLF stay CRLF until something re-checks them out, and
  `git checkout -- .` will not do it — a file git considers clean is not
  re-smudged. Measured: the file must be removed from the index's stat
  cache first. From the worktree root, on a committed tree:

  ```
  git rm --cached -r -q . && git reset --hard
  ```

  That is local only. It writes no commit, changes no blob, and cannot
  conflict with another branch.

  Until it is run, the symptom persists in that worktree ALONE, and it
  is now self-healing per file: `git checkout -- <file>` on a file that
  has gone phantom-modified rewrites it LF and it never returns.
- `.gitattributes` grew 29 lines and lost none. The five original rules
  and their comments are untouched.
- **`art/build.py`'s `source_hash` is unaffected**, which is the one
  thing that could have gone quietly wrong here: `*.py text eol=lf` was
  already in force, still wins over the catch-all, and no `.py` byte
  changes. Verified with `just test-unit` (`test_art_assets.gd` re-hashes
  the generators through Godot and would report "generated/ is stale").

## Revisit trigger

A pattern added to `.gitattributes` that `tests/test_line_endings.gd`'s
matcher cannot read — it fails loudly on one rather than skipping it,
because a scan that silently stops applying a rule goes vacuously green,
which is the failure mode D-022's audit block exists for.
