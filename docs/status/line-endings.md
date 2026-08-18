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
