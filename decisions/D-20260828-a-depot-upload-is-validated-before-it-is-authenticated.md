# D-20260828 · 2026-08-28 · Accepted — a depot upload is validated before it is authenticated

**Decision:** the Steam depot loop (D-094 criterion 2, #185) splits at the
credential, and everything on this side of that split is complete,
testable and run. Five clauses:

1. **`just steam-upload` is DRY by default and `live` must be typed.**
   An upload is outward-facing and cannot be taken back from a worktree.
   Same rule as `just reap-orphans`, which dry-runs unless `APPLY=1` and
   was twice caught proposing to delete a live agent's containers.
2. **A dry run checks everything a live one does.** Both modes run the
   same validation and generate the same build scripts; only the tail
   differs. A rehearsal that checked less would be a rehearsal of a
   different performance — so the first authenticated run is the only
   step that has not already been performed.
3. **Every RULE lives in `steam-depot.sh`, not in the recipe.** The same
   reason `recipe-arg.sh`, `instance-id.sh` and `gate-check.sh` are
   scripts: the test estate cannot reach a recipe body at all, and every
   rule here is one that has to be watched failing before it is trusted.
   The recipe decides only whether to authenticate.
4. **The VDFs are GENERATED from the environment, not committed.** This
   is the one place the work departs from #185's wording ("app_build /
   depot_build VDF scripts, committed"), and the reason is that a
   committed build script has the app id and every depot id baked into
   it — precisely the identity that does not exist yet. Committing one
   would mean committing placeholders a real run must remember to
   replace, which is the shape of defect this project keeps paying for.
   The **layout** is committed, in `steam-depot.sh`; the ids arrive from
   the environment and are validated there.
5. **`default` is refused as a branch name.** On Steam that is the
   branch every owner of the app receives, so setting a build live there
   is publishing, and D-087 is explicit that M8 is Steam-READY and not
   launched. A rule rather than a warning because the mistake is one
   word long, irreversible from here, and would be made by a person
   typing a branch name at midnight.

**Not done, and not doable from a worktree:** criterion 2's second half —
*a fresh machine installs and runs it from Steam*. That needs a
Steamworks partner account, the app fee, an app id, depot ids, a login
and a second machine. `just steam-upload live` is written and refuses
loudly on each of those; **nobody has run it against Steam.**

## Rationale

The identity/credential split is the whole design:

| | what it is | where it lives |
|---|---|---|
| **Identity** | app id, depot ids, branch | not secret, not known yet — environment, validated, printed in every plan |
| **Credential** | the steamcmd login | secret, and `steam-depot.sh` never reads one at all |

`validate`, `vdf` and `plan` are complete without a credential, which is
what makes the whole loop testable today against an app that does not
exist. The alternative — a feature that can only be exercised once the
owner has paid Valve — would arrive on the day it is first needed with
every one of its rules unobserved.

**Why steamcmd is not bootstrapped.** Same call as Blender
(D-20260821): it is an ordinary tool, it self-updates on every run, and
a repo-pinned private copy of a self-updating downloader is worse than
none. It is found, reported by `just doctor`, and never installed —
`bootstrap.ps1`'s promise that a fresh clone installs nothing
system-wide is untouched.

**Why there is no password environment variable.** Steam Guard makes an
unattended password login fail anyway on a machine that has not been
trusted, so a password on the command line would be a secret in a
process list that does not even remove the prompt. The documented path
is one interactive `steamcmd +login` per machine and a cached sentry.
`tests/test_steam_depot.gd` fails if `EDOTMW_STEAM_PASSWORD` ever
appears in the justfile or the script.

## Rejected alternatives

- **Committing the VDFs with placeholder ids**, as #185's wording says.
  See clause 4. A placeholder that a real run must remember to replace
  is exactly the "declared and never re-read" family, with an upload
  attached.
- **Putting the app id and depot ids in a committed config file.** They
  are not secret, so this is tempting. It is wrong for a different
  reason: they do not exist, so the file would ship as a lie until the
  owner edits it, and nothing would fail if they edited it wrongly. The
  environment cannot ship as a lie — it is either set or the run
  refuses.
- **`preview 1` in the app build script as the dry run.** That is
  Steam's own rehearsal, and it is genuinely useful — but it still
  authenticates, so it cannot be what `just steam-upload dry` is. Named
  in the generated script's comment so the owner finds it once they have
  credentials.
- **Uploading the Windows *server* build as a depot.** D-088 puts the
  authoritative simulation in the host's process, so a tester installs a
  client and nothing else. A depot nothing installs would be an upload
  with no consumer. The Linux server depot is included only when its id
  is set — opt-in, because `just export` already produces the binary and
  official-dedicated-later will want it.
- **Host-gating the recipe.** The gate rations MEMORY (D-20260818) and
  an upload is network-bound. `just export`, which this depends on and
  deliberately does not run for you, is gated.

## Consequences

- **Fifteen tests, and every one was observed to fail**, in docker,
  against a deliberately broken script or justfile: the numeric app id,
  the public-branch refusal, the empty-depot refusal, the
  all-problems-in-one-run rule, the version stamp, `setlive`, the
  no-credential-in-a-build-script rule, the optional depot, the
  no-VDF-for-an-invalid-configuration rule, the dry default, the
  `recipe-arg.sh` guard, the validate-before-login ordering, and the
  password ban.
- **One of those tests was weak and the perturbation is what found it.**
  It asserted that an unconfigured depot's *named* id was absent — and a
  bug that invents a different id writes `depot_build_999.vdf` and
  passes. Observed: it did, 15/15 green with the bug in. It counts
  depot scripts now. **A test that names the value it expects to be
  missing cannot see a wrong value under another name.**
- **The upload is stamped with `project.godot`'s version**, the same
  literal `build_version.gd` prints at runtime
  (D-20260827-the-build-is-exported-from-one-version). That is what
  makes #185's "the installed build prints the version the recipe
  uploaded" a comparison rather than a hope.
- **`just doctor` reports the configuration**, so "why did
  `steam-upload` refuse" is answered where people already look.
- The owner's one-time setup is `docs/status/m8-steam-depot.md`.

## Open — the owner's call, deliberately not taken here

**Steam Playtest may be the better vehicle than a password-protected
branch.** #185 raises it: a separate free app testers request access to,
purpose-built for exactly this stage, postdating D-094's framing.

**The pipeline is identical either way** — a Playtest app has its own app
id and its own depots and consumes the same `app_build`/`depot_build`
scripts — so adopting it is `EDOTMW_STEAM_APP_ID` pointing at the
Playtest app and *nothing in this repo changing*. It is left open rather
than picked quietly because D-094's own revisit trigger says a criterion
found unverifiable as written is amended **in the open**. Whichever is
chosen, this loop serves it, and D-094 criterion 2 should be amended in
its own file to say which.

## Revisit trigger

The first `just steam-upload live` that reaches Steam. Everything above
is a claim about what the loop does locally; the moment one upload
succeeds, this entry gains an amendment saying what Steam actually did
with the generated scripts — the `setlive` semantics in particular,
which are documented by Valve and unverified here.
