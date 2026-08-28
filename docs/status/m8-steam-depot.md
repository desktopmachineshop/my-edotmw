**The depot upload exists and has never been authenticated
(D-20260828-a-depot-upload-is-validated-before-it-is-authenticated, #185,
D-094 criterion 2).** `just steam-upload` validates the whole
configuration, generates the Steam build scripts from `just export`'s
output and prints exactly what a live run would execute — **without a
credential, without steamcmd and without a network**. The `live` half is
written and refuses loudly; **nobody has run it against Steam**, because
there is no app id to run it against yet.

```
just steam-upload            # validate + generate, send nothing
just steam-upload live       # the above, then steamcmd
just doctor                  # reports what is configured and what is not
```

## The owner's one-time setup

Everything below is outside this repo, and none of it is a secret except
the last line.

1. **A Steamworks partner account and the app fee.** This is the
   prerequisite #185 names, and nothing here can substitute for it. It
   yields an **app id**.
2. **On the partner site, create the depots.** One is enough: the
   Windows client. The site mints a **depot id** per depot.
3. **Create a private branch** under *SteamPipe → Builds*. Call it
   `alpha` (the default here) or anything except `default`, and **set a
   password on it**: D-087 is that M8 is Steam-ready and not launched, so
   a build must never be visible to anyone who has not been given the
   password.
4. **Set the identity in your shell**, once, in your profile:

   ```sh
   export EDOTMW_STEAM_APP_ID=1234560
   export EDOTMW_STEAM_DEPOT_WINDOWS=1234561
   export EDOTMW_STEAM_USER=your_steam_login
   # optional:
   # export EDOTMW_STEAM_BRANCH=alpha          # the default
   # export EDOTMW_STEAM_DEPOT_LINUX_SERVER=1234562
   # export EDOTMW_STEAMCMD=/c/steamcmd/steamcmd.exe
   ```

5. **Install steamcmd** from Valve and either put it on PATH or name it
   with `EDOTMW_STEAMCMD`. This repo does **not** install it, for the
   same reason it does not install Blender (D-20260821): it is an
   ordinary tool that self-updates on every run, and a repo-pinned
   private copy of a self-updating downloader is worse than none.
6. **Log in once, interactively**, so steamcmd caches the Steam Guard
   sentry for this machine:

   ```sh
   steamcmd +login your_steam_login +quit
   ```

   **There is no password environment variable and there will not be
   one.** Steam Guard makes an unattended password login fail anyway on
   a machine that has not been trusted, so a password on the command
   line would be a secret in a process list that does not even remove
   the prompt. `tests/test_steam_depot.gd` fails if one appears.

## The loop

```sh
just export                  # 267 MB windows client, ~2 min
just steam-upload            # dry: says exactly what live would do
just steam-upload live       # uploads
```

Then on the partner site, *Builds* → set the build live on the branch.
`setlive` in the generated script asks for that, but Steam still decides
when it happens.

## Five things worth knowing before touching any of it

- **Dry is the default, and `live` has to be typed.** An upload is
  outward-facing and cannot be taken back from a worktree. Same rule as
  `just reap-orphans`, which dry-runs unless `APPLY=1` and was twice
  caught proposing to delete a live agent's containers.
- **A dry run checks everything a live one does.** The two run the same
  validation and generate the same build scripts; only the tail differs.
  A rehearsal that checked less would be a rehearsal of a different
  performance — so the first authenticated run is the only step that has
  not already been performed.
- **`default` is refused as a branch name.** On Steam that is the branch
  every owner of the app receives, so setting a build live there is
  publishing. The mistake is one word long and irreversible from here.
- **The VDFs are GENERATED, not committed**, which is the one place this
  departs from #185's wording. A committed build script has the app id
  and every depot id baked into it — exactly the identity that does not
  exist yet — so committing one would mean committing placeholders that
  a real run must remember to replace. The **layout** is committed, in
  `steam-depot.sh`; the ids arrive from the environment.
- **The version an upload is stamped with is the one in
  `project.godot`** (`application/config/version`, D-20260827), the same
  literal `build_version.gd` prints at runtime. That is what makes
  #185's "the installed build prints the version the recipe uploaded" a
  comparison rather than a hope.

## Open, and deliberately not decided here

**Steam Playtest may be the better vehicle than a password-protected
branch**, and #185 raises it: it is a separate free app that testers
request access to, purpose-built for exactly this stage, and it postdates
D-094's framing. **The pipeline is identical either way** — a Playtest
app has its own app id and its own depots and takes the same
`app_build`/`depot_build` scripts — so switching is `EDOTMW_STEAM_APP_ID`
pointing at the Playtest app and nothing else in this repo changing.

It is left as the owner's call rather than picked quietly, because
D-094's own revisit trigger says a criterion found unverifiable as
written gets amended **in the open**. Whichever is chosen, this loop
serves it.

## Not done, and not doable from here

D-094 criterion 2's second half — *a fresh machine installs and runs it
from Steam* — needs an app id, a login, an upload that actually happened
and a second machine. None of that is reachable from a worktree. When
the owner first runs `just steam-upload live`, the thing to check is that
the installed build's first line prints the same version the upload was
stamped with.
