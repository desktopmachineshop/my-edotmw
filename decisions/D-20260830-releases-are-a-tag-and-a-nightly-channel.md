# D-20260830 · 2026-08-30 · Accepted — releases are a tag and a nightly channel

**Decision:** the game ships from GitHub Releases on this repository,
which the owner intends to make public. Two pipelines, one build path,
and an in-game update check. Six clauses:

1. **An official release IS a `v*` tag.** Pushing one runs
   `.github/workflows/release.yml`: the same `just export` / `just
   package` recipes a checkout runs, all three targets, sha256s, one
   GitHub Release. Tagging is the deliberate human act, exactly as
   `just bench-record` is — no release happens as a side effect of
   anything.
2. **The tag must equal `project.godot`'s version, or the workflow
   refuses.** The version has ONE writer
   (`D-20260827-the-build-is-exported-from-one-version`); a release
   named after anything else would be a second one. Bump
   `application/config/version` first, then tag `v<that>`.
3. **The nightly is a ROLLING PRERELEASE named `nightly`, published only
   when the nightly `test-load` gate is green.** A red gate leaves
   yesterday's build standing; no build the wire gate failed reaches a
   player. It carries windows-client and linux-server — the player and
   whoever hosts their session (`docs/alpha/runbook.md`) — and is
   deleted and recreated each night so the tag moves with the release.
4. **A nightly binary's version string is the same as the last official
   one, on purpose.** D-081 requires two clean clones of one commit to
   export identical bytes, so a sha or date in the build is forbidden
   (`build_version.gd` says so in its own words). Nightly identity lives
   in the release title and notes; mixed builds meeting each other is
   already handled where it matters, by #179's join handshake.
5. **The client checks for updates from the MAIN MENU, once per
   process** (`update_check.gd`). GitHub's `releases/latest` API
   excludes prereleases, so the check tracks official tags only and the
   nightly channel stays opt-in. Every failure — offline, the 404 a
   private repo answers, a malformed body — is silence, because "could
   not check" is not something a player can act on. The button ALWAYS
   opens the URL constructed from `UpdateCheck.REPO`, never one off the
   wire — `game_browser.gd`'s rule, applied before it costs anything.
   Firing from the menu rather than `_ready()` is load-bearing twice
   over: autoconnected launches (every headless harness in the estate)
   never show the menu, so CI never talks to GitHub.
6. **Phase 2 — a self-applying updater — is deliberately NOT here.**
   Windows cannot replace a running exe, so anything past
   notify-and-link needs either a swap-on-restart helper shipped in the
   zip or a real installer (Inno Setup class). Both are their own
   decision with their own failure modes (a half-applied swap is a
   corrupted install); notify-and-link plus the handshake's refusal
   covers the harm — a stale build cannot silently play — while that
   decision waits.

## Rationale

The owner's call (2026-08-30): the repo public was "the goal all along",
downloads on the repo, an update check in the game, Steam deferred. That
retires itch.io as the planned alpha channel — `just publish-itch` stays,
unused, because it is the steamcmd rehearsal (#185) and the recipe's
refusal path is its tested state.

**Why the nightly gates on `test-load` and not on more:** the nightly
workflow already runs the wire gate and the picture recipes. The
pictures need a human eye by design ("nothing here asserts about a
picture; that is not a robot's job"), so chaining the publish on them
would gate a build on a check nobody automated. The wire gate is the one
automated verdict the estate trusts.

**Why a rolling tag rather than dated nightly tags:** a tag per night is
a hundred tags a quarter that nobody will ever check out, and the
stable asset URL (`releases/download/nightly/<zip>`) is what a future
phase-2 updater would poll. History for nightlies is the git log itself.

**Why the update check is not telemetry:** it is one anonymous HTTPS GET
of a public API, sends nothing about the player, and `testers.md`
discloses it in the same breath as the no-telemetry promise — a promise
kept in the letter and the spirit is worth more than one kept quietly.

## Rejected

- **itch.io + butler as the channel.** Auto-updating deltas via the itch
  app are genuinely better distribution mechanics, but the owner's goal
  is the public repo, and two channels is two places for a stale build
  to stand.
- **A sha or timestamp in the nightly binary's version.** Breaks D-081's
  reproducibility outright; see clause 4.
- **Opening `html_url` from the API response.** One compromised or
  spoofed body could send every player's browser anywhere. The response
  contributes exactly one datum — the version — and nothing else.
- **Checking for updates in `_ready()`.** Every autoconnected harness in
  CI would knock on GitHub's door once per run, and a player who launched
  straight into a match would pay a DNS lookup for a banner they cannot
  see.

## Owner actions this does not perform

Making the repo public is the owner's switch, and two things come first:
a LICENSE decision (no file means all-rights-reserved — readable, not
reusable; that may be exactly right for a commercial game, but it should
be chosen) and a history secrets scan. Until the flip, the release
workflow works privately and the update check 404s into silence.
